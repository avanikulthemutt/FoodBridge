import os, tempfile
from datetime import date, timedelta, datetime, timezone
from fastapi.testclient import TestClient
from foodbridge_app import db

fd, path = tempfile.mkstemp(suffix='.sqlite3'); os.close(fd)
model_path = tempfile.mkdtemp(prefix='foodbridge-test-models-')
os.environ['FOODBRIDGE_MODEL_DIR'] = model_path
db.DB_PATH = path
db.init_db()
from foodbridge_app.main import app
client = TestClient(app)

def register(role,email,name):
    payload={'name':name,'email':email,'password':'SecurePass123','role':role,'phone':'1234567890','address':'Main Road','city':'Bengaluru'}
    if role=='provider': payload.update(organization_name='Test Kitchen',organization_type='Canteen')
    else: payload.update(ngo_name='Test NGO',collection_capacity=100,people_served=50)
    r=client.post('/api/auth/register',json=payload); assert r.status_code==200,r.text
    return r.json()['access_token']

def headers(t): return {'Authorization':'Bearer '+t}

def test_end_to_end_core():
    assert client.get('/health').json()['status']=='ok'
    p=register('provider','p@example.com','Provider'); n=register('ngo','n@example.com','NGO')
    # NGO cannot browse/accept before admin verification.
    assert client.get('/api/donations',headers=headers(n)).json()==[]
    # Seed an admin using the same DB connection and verify the NGO.
    from foodbridge_app.security import hash_password
    with db.connect() as c:
        aid=c.execute("INSERT INTO users(name,email,password_hash,role) VALUES(?,?,?,'admin')",('Admin','a@example.com',hash_password('AdminPass123'))).lastrowid
        nid=c.execute("SELECT id FROM users WHERE email='n@example.com'").fetchone()[0]
    a=client.post('/api/auth/login',json={'email':'a@example.com','password':'AdminPass123'}).json()['access_token']
    assert client.post(f'/api/admin/ngos/{nid}/verify',headers=headers(a),json={'status':'verified'}).status_code==200
    # Validation and historical records.
    bad={'record_date':str(date.today()-timedelta(days=1)),'meal_type':'Lunch','food_category':'Indian','prepared':10,'consumed':11}
    assert client.post('/api/records',headers=headers(p),json=bad).status_code==422
    future={**bad,'record_date':str(date.today()+timedelta(days=1)),'prepared':10,'consumed':5}
    assert client.post('/api/records',headers=headers(p),json=future).status_code==422
    for i in range(14):
        d=date.today()-timedelta(days=14-i)
        row={'record_date':str(d),'meal_type':'Lunch','food_category':'Indian','prepared':180,'consumed':150+(i%4)*3,'event_indicator':False,'holiday_indicator':False}
        assert client.post('/api/records',headers=headers(p),json=row).status_code==200
    trained=client.post('/api/ml/train',headers=headers(p)); assert trained.status_code==200,trained.text
    assert trained.json()['trained'] is True
    assert 'baseline_mae' in trained.json()['metrics'] and os.path.exists(trained.json()['model_path'])
    assert client.get('/api/ml/evaluations',headers=headers(p)).status_code==200
    assert trained.json()['metrics']['training_records'] >= 5
    assert trained.json()['metrics']['testing_records'] >= 2
    pred=client.post('/api/predictions',headers=headers(p),json={'prediction_date':str(date.today()+timedelta(days=1)),'meal_type':'Lunch','food_category':'Indian','planned_preparation':200})
    assert pred.status_code==200,pred.text
    assert pred.json()['estimated_surplus']>=0 and pred.json()['donation_created'] is False
    sim=client.post('/api/simulator',headers=headers(p),json={'predicted_demand':155,'quantities':[200,180,160,150]})
    assert [x['estimated_surplus'] for x in sim.json()]==[45,25,5,0]
    # Record the actual prepared/consumed surplus before creating a donation.
    actual_date=date.today()
    comparison=client.post('/api/predictions',headers=headers(p),json={'prediction_date':str(actual_date),'meal_type':'Lunch','food_category':'Indian','planned_preparation':180})
    assert comparison.status_code==200
    comparison2=client.post('/api/predictions',headers=headers(p),json={'prediction_date':str(actual_date),'meal_type':'Lunch','food_category':'Indian','planned_preparation':170})
    assert comparison2.status_code==200
    actual=client.post('/api/records',headers=headers(p),json={'record_date':str(actual_date),'meal_type':'Lunch','food_category':'Indian','prepared':10,'consumed':5})
    assert actual.status_code==200,actual.text
    with db.connect() as c: food_record_id=c.execute('SELECT id FROM food_records WHERE provider_id=(SELECT id FROM users WHERE email=\'p@example.com\') AND record_date=?',(str(actual_date),)).fetchone()[0]
    # Only actual verified surplus can be listed.
    now=datetime.now(timezone.utc)
    donation={'food_record_id':food_record_id,'food_name':'Rice meal','food_category':'Indian','quantity':5,'meal_type':'Lunch','food_type':'Vegetarian',
      'preparation_time':(now-timedelta(minutes=20)).isoformat(),'pickup_start':(now+timedelta(minutes=5)).isoformat(),
      'pickup_deadline':(now+timedelta(hours=1)).isoformat(),'safe_consumption_deadline':(now+timedelta(hours=2)).isoformat(),
      'storage_method':'Insulated containers','pickup_location':'Bengaluru, India','contact_information':'9999999999','provider_verified':True}
    created=client.post('/api/donations',headers=headers(p),json=donation); assert created.status_code==200,created.text
    did=created.json()['id']
    # Keep donation audit links and allocated quantities consistent with later record edits.
    assert client.put(f'/api/records/{food_record_id}',headers=headers(p),json={'record_date':str(actual_date),'meal_type':'Lunch','food_category':'Indian','prepared':10,'consumed':6}).status_code==409
    assert client.put(f'/api/records/{food_record_id}',headers=headers(p),json={'record_date':str(actual_date-timedelta(days=1)),'meal_type':'Lunch','food_category':'Indian','prepared':10,'consumed':5}).status_code==409
    assert client.delete(f'/api/records/{food_record_id}',headers=headers(p)).status_code==409
    listing=client.get('/api/donations',headers=headers(n)); assert listing.status_code==200 and len(listing.json())==1
    accepted=client.post(f'/api/donations/{did}/status',headers=headers(n),json={'status':'Accepted'}); assert accepted.status_code==200,accepted.text
    # A second verified NGO cannot take an already accepted donation.
    n2=register('ngo','n2@example.com','NGO 2')
    with db.connect() as c:
        n2id=c.execute("SELECT id FROM users WHERE email='n2@example.com'").fetchone()[0]
    assert client.post(f'/api/admin/ngos/{n2id}/verify',headers=headers(a),json={'status':'verified'}).status_code==200
    assert client.post(f'/api/donations/{did}/status',headers=headers(n2),json={'status':'Accepted'}).status_code==403
    for status in ['Pickup Scheduled','Picked Up','Delivered','Completed']:
        payload={'status':status,'remarks':'test'}
        if status=='Pickup Scheduled':
            payload['pickup_time']=(now+timedelta(hours=3)).isoformat()
            assert client.post(f'/api/donations/{did}/status',headers=headers(n),json=payload).status_code==422
            payload['pickup_time']=(now+timedelta(minutes=10)).isoformat()
        r=client.post(f'/api/donations/{did}/status',headers=headers(n),json=payload); assert r.status_code==200,r.text
    analytics=client.get('/api/analytics',headers=headers(p)).json()
    assert analytics['prediction_comparisons']>=2
    with db.connect() as c:
        latest_prevention=c.execute('SELECT COALESCE(SUM(potential_prevention),0) FROM predictions p WHERE provider_id=(SELECT id FROM users WHERE email=\'p@example.com\') AND id=(SELECT MAX(p2.id) FROM predictions p2 WHERE p2.provider_id=p.provider_id AND p2.prediction_date=p.prediction_date AND p2.meal_type=p.meal_type AND p2.food_category=p.food_category)').fetchone()[0]
    assert analytics['estimated_potential_prevention']==latest_prevention
    assert client.get('/api/analytics/trends',headers=headers(p)).status_code==200
    assert analytics['confirmed_donated_quantity']==5 and analytics['remaining_actual_waste']==analytics['actual_surplus']-5
    assert len(client.get('/api/donations?scope=collections',headers=headers(n)).json())==1
    assert client.get('/api/donations/'+str(did)+'/history',headers=headers(n)).status_code==200

def test_password_and_scenario_math():
    from foodbridge_app.security import hash_password,verify_password
    from foodbridge_app.ml import scenario
    h=hash_password('abc12345'); assert verify_password('abc12345',h); assert not verify_password('wrong',h)
    x=scenario(155,200,3); assert x['estimated_surplus']==45 and x['recommended_preparation']==160
    assert scenario(0,0)['waste_percentage']==0


def test_insufficient_history_is_honest_fallback():
    from foodbridge_app.ml import predict
    value,source,explanation=predict([],999,'2026-12-01','Lunch','General')
    assert value==0 and source=='Fallback recent average' and 'Insufficient' in explanation


def test_csv_duplicate_and_admin_safety_review():
    p=register('provider','csv@example.com','CSV Provider')
    n=register('ngo','csvngo@example.com','CSV NGO')
    # Create an admin and verify this NGO.
    from foodbridge_app.security import hash_password
    with db.connect() as c:
        aid=c.execute("INSERT INTO users(name,email,password_hash,role) VALUES(?,?,?,'admin')",('Admin 2','admin2@example.com',hash_password('AdminPass123'))).lastrowid
        nid=c.execute("SELECT id FROM users WHERE email='csvngo@example.com'").fetchone()[0]
    a=client.post('/api/auth/login',json={'email':'admin2@example.com','password':'AdminPass123'}).json()['access_token']
    client.post(f'/api/admin/ngos/{nid}/verify',headers=headers(a),json={'status':'verified'})
    today=str(date.today()); tomorrow=str(date.today()+timedelta(days=1))
    csvdata='record_date,meal_type,food_category,prepared,consumed\n'+f'{today},Lunch,Indian,20,15\n'+f'{today},Lunch,Indian,20,15\n'+f'{tomorrow},Dinner,Rice,10,12\n'
    imported=client.post('/api/records/import',headers=headers(p),files={'file':('records.csv',csvdata,'text/csv')})
    assert imported.status_code==200 and imported.json()=={'inserted':1,'skipped_invalid_or_duplicate':2}
    exported=client.get('/api/records/export',headers=headers(p)); assert exported.status_code==200 and today in exported.text
    # Unknown storage is held from NGO discovery until admin review.
    with db.connect() as c:
        uid=c.execute("SELECT id FROM users WHERE email='csv@example.com'").fetchone()[0]
        rid=c.execute("SELECT id FROM food_records WHERE provider_id=? AND record_date=?",(uid,today)).fetchone()[0]
    now=datetime.now(timezone.utc)
    payload={'food_record_id':rid,'food_name':'Prepared meal','food_category':'Indian','quantity':5,'meal_type':'Lunch','food_type':'Vegetarian',
      'preparation_time':(now-timedelta(minutes=10)).isoformat(),'pickup_start':now.isoformat(),'pickup_deadline':(now+timedelta(hours=1)).isoformat(),
      'safe_consumption_deadline':(now+timedelta(hours=2)).isoformat(),'storage_method':'Unknown','pickup_location':'Bengaluru, India','contact_information':'9999999999','provider_verified':True}
    made=client.post('/api/donations',headers=headers(p),json=payload); assert made.status_code==200 and made.json()['safety_review_required'] is True
    did=made.json()['id']; assert client.get('/api/donations',headers=headers(n)).json()==[]
    assert client.post(f'/api/admin/donations/{did}/safety-review',headers=headers(a),json={'approved':True}).status_code==200
    assert len(client.get('/api/donations',headers=headers(n)).json())==1


def test_authentication_role_boundaries_and_provider_isolation():
    p1=register('provider','isolated1@example.com','Provider One')
    p2=register('provider','isolated2@example.com','Provider Two')
    assert client.get('/api/me').status_code==401
    assert client.post('/api/auth/login',json={'email':'isolated1@example.com','password':'wrong-password'}).status_code==401
    assert client.post('/api/auth/register',json={'name':'Admin User','email':'selfadmin@example.com','password':'SecurePass123','role':'admin','phone':'1234567890','address':'Main Road','city':'Bengaluru'}).status_code==422
    assert client.get('/api/admin/overview',headers=headers(p1)).status_code==403
    row={'record_date':str(date.today()),'meal_type':'Breakfast','food_category':'Fruit','prepared':20,'consumed':18}
    created=client.post('/api/records',headers=headers(p1),json=row)
    assert created.status_code==200,created.text
    assert client.get('/api/records',headers=headers(p2)).json()==[]
    rid=created.json()['id']
    assert client.put(f'/api/records/{rid}',headers=headers(p2),json=row).status_code==404
    assert client.delete(f'/api/records/{rid}',headers=headers(p2)).status_code==404

def test_crud_rbac_simulator_and_cancel():
    p=register('provider','crud@example.com','CRUD Provider')
    p2=register('provider','otherprovider@example.com','Other Provider')
    n=register('ngo','crudngo@example.com','CRUD NGO')
    # Bad password and provider-only access.
    assert client.post('/api/auth/login',json={'email':'crud@example.com','password':'wrongpass'}).status_code==401
    assert client.get('/api/records',headers=headers(n)).status_code==403
    row={'record_date':str(date.today()),'meal_type':'Lunch','food_category':'Test meals','prepared':12,'consumed':7}
    created=client.post('/api/records',headers=headers(p),json=row); assert created.status_code==200
    rid=created.json()['id']
    assert client.get('/api/records',headers=headers(p2)).json()==[]
    assert client.put(f'/api/records/{rid}',headers=headers(p2),json=row).status_code==404
    updated={**row,'prepared':14,'consumed':8,'notes':'edited'}
    assert client.put(f'/api/records/{rid}',headers=headers(p),json=updated).status_code==200
    assert client.get('/api/records',headers=headers(p)).json()[0]['surplus']==6
    assert client.delete(f'/api/records/{rid}',headers=headers(p)).status_code==200
    assert client.delete(f'/api/records/{rid}',headers=headers(p)).status_code==404
    sim=client.post('/api/simulator',headers=headers(p),json={'predicted_demand':155,'quantities':[200,180,160,150]}).json()
    assert sim[0]['waste_percentage']==22.5 and sim[2]['recommended_preparation']==160
    assert sim[2]['potential_surplus_reduction']==40
    assert 'recommendation' in sim[2]
    assert client.post('/api/simulator',headers=headers(p),json={'predicted_demand':155,'quantities':[-1]}).status_code==422
    # Create actual record and cancel its available donation.
    row={'record_date':str(date.today()),'meal_type':'Dinner','food_category':'Pulao','prepared':10,'consumed':5}
    created=client.post('/api/records',headers=headers(p),json=row); assert created.status_code==200
    with db.connect() as c:
        uid=c.execute("SELECT id FROM users WHERE email='crud@example.com'").fetchone()[0]
        food_id=c.execute("SELECT id FROM food_records WHERE provider_id=? AND food_category='Pulao'",(uid,)).fetchone()[0]
    now=datetime.now(timezone.utc)
    donation={'food_record_id':food_id,'food_name':'Pulao','food_category':'Pulao','quantity':5,'meal_type':'Dinner','food_type':'Vegetarian',
      'preparation_time':(now-timedelta(minutes=10)).isoformat(),'pickup_start':now.isoformat(),'pickup_deadline':(now+timedelta(hours=1)).isoformat(),
      'safe_consumption_deadline':(now+timedelta(hours=2)).isoformat(),'storage_method':'Insulated box','pickup_location':'Bengaluru, India','contact_information':'9999999999','provider_verified':True}
    overbook={**donation,'quantity':6}
    assert client.post('/api/donations',headers=headers(p),json=overbook).status_code==422
    expired={**donation,'preparation_time':(now-timedelta(minutes=10)).isoformat(),'pickup_start':(now-timedelta(minutes=8)).isoformat(),'pickup_deadline':(now-timedelta(minutes=2)).isoformat(),'safe_consumption_deadline':(now-timedelta(minutes=1)).isoformat()}
    assert client.post('/api/donations',headers=headers(p),json=expired).status_code==422
    made=client.post('/api/donations',headers=headers(p),json=donation); assert made.status_code==200
    did=made.json()['id']
    assert client.get('/api/donations',headers=headers(p2)).json()==[]
    assert client.get(f'/api/matches/{did}',headers=headers(p2)).status_code==403
    assert client.post(f'/api/donations/{did}/status',headers=headers(p),json={'status':'Cancelled'}).status_code==200
    assert client.get('/api/donations',headers=headers(p)).json()[0]['status']=='Cancelled'
