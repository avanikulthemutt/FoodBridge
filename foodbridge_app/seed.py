"""Create local demo accounts and illustrative records. Change demo passwords before deployment."""
from .db import init_db, connect
from .security import hash_password
from datetime import date, timedelta

def seed():
 init_db()
 with connect() as c:
  if c.execute('SELECT COUNT(*) FROM users').fetchone()[0]: return
  accounts=[('FoodBridge Admin','admin@foodbridge.example.com','Admin@12345','admin'),('Demo Canteen','provider@foodbridge.example.com','Provider@12345','provider'),('Demo NGO','ngo@foodbridge.example.com','Ngo@1234567','ngo')]
  ids={}
  for name,email,pw,role in accounts: ids[role]=c.execute('INSERT INTO users(name,email,password_hash,role,phone) VALUES(?,?,?,?,?)',(name,email,hash_password(pw),role,'9999999999')).lastrowid
  c.execute('INSERT INTO providers(user_id,organization_name,organization_type,address,city,food_categories,contact_person) VALUES(?,?,?,?,?,?,?)',(ids['provider'],'Demo College Canteen','College Canteen','MG Road','Bengaluru','Indian meals','Demo Canteen'))
  c.execute('INSERT INTO ngos(user_id,ngo_name,address,city,service_area,people_served,collection_capacity,food_requirements,preferred_categories,verification_status) VALUES(?,?,?,?,?,?,?,?,?,?)',(ids['ngo'],'Demo Community Kitchen','Indiranagar','Bengaluru','East Bengaluru',120,250,'Indian meals','Vegetarian,Indian','verified'))
  # Synthetic sample history, intentionally labelled in README and UI.
  import random
  random.seed(7)
  last_wed=date.today()-timedelta(days=((date.today().weekday()-2)%7 or 7))
  for i in range(35):
   d=date.today()-timedelta(days=35-i); demand=max(80,round(155+12*((d.weekday()+1)%4)+random.randint(-12,12)))
   prep=demand+random.randint(5,30); meal=['Breakfast','Lunch','Dinner'][i%3]
   if d==last_wed and meal=='Lunch': continue
   c.execute('INSERT INTO food_records(provider_id,record_date,meal_type,food_category,prepared,consumed,surplus,event_indicator,holiday_indicator,weather,notes) VALUES(?,?,?,?,?,?,?,?,?,?,?)',(ids['provider'],str(d),meal,'Indian meals',prep,demand,prep-demand,0,0,'Not recorded','Synthetic demo record'))
  c.execute('INSERT INTO food_records(provider_id,record_date,meal_type,food_category,prepared,consumed,surplus,event_indicator,holiday_indicator,weather,notes) VALUES(?,?,?,?,?,?,?,?,?,?,?)',(ids['provider'],str(last_wed),'Lunch','Indian meals',200,155,45,0,0,'Not recorded','Illustrative Wednesday lunch demonstration record; synthetic sample data'))
  c.execute("INSERT INTO notifications(user_id,title,message,notification_type) VALUES(?,?,?,?)",(ids['provider'],'Welcome to FoodBridge','Sample records are synthetic. Add your own historical data before relying on forecasts.','system'))

if __name__=='__main__': seed(); print('Demo data ready')
