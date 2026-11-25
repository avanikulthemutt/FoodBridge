"""Leakage-aware per-provider demand forecasting and simulator maths."""
from pathlib import Path
from datetime import date
import hashlib, json
import joblib, numpy as np, pandas as pd, os
from sklearn.ensemble import RandomForestRegressor

from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

MODEL_DIR=Path(os.getenv('FOODBRIDGE_MODEL_DIR', str(Path(__file__).resolve().parent.parent/'models'))).expanduser(); MODEL_DIR.mkdir(parents=True, exist_ok=True)
FEATURES=['weekday','meal_code','category_code','event_indicator','holiday_indicator','lag_1','lag_7','lag_prepared','lag_surplus','rolling_mean_7']
MEALS={'Breakfast':0,'Lunch':1,'Dinner':2}
def _fingerprint(records):
    raw=json.dumps(records,sort_keys=True,default=str,separators=(',',':')).encode()
    return hashlib.sha256(raw).hexdigest()

def _features(df):
    x=df.copy(); x['record_date']=pd.to_datetime(x['record_date']); x=x.sort_values('record_date')
    x['weekday']=x.record_date.dt.weekday
    x['meal_code']=x.meal_type.map(MEALS).fillna(1)
    cats={v:i for i,v in enumerate(sorted(x.food_category.fillna('General').astype(str).unique()))}
    x['category_code']=x.food_category.fillna('General').astype(str).map(cats)
    grp=x.groupby(['meal_type','food_category'],dropna=False)
    x['lag_1']=grp.consumed.shift(1); x['lag_7']=grp.consumed.shift(7)
    x['lag_prepared']=grp.prepared.shift(1); x['lag_surplus']=grp.surplus.shift(1)
    x['rolling_mean_7']=grp.consumed.transform(lambda s:s.shift(1).rolling(7,min_periods=1).mean())
    prior_consumed=x.consumed.shift(1).expanding(min_periods=1).mean().fillna(0)
    prior_prepared=x.prepared.shift(1).expanding(min_periods=1).mean().fillna(0)
    prior_surplus=x.surplus.shift(1).expanding(min_periods=1).mean().fillna(0)
    for col in ['lag_1','lag_7','rolling_mean_7']:
        x[col]=x[col].fillna(prior_consumed)
    x['lag_prepared']=x['lag_prepared'].fillna(prior_prepared)
    x['lag_surplus']=x['lag_surplus'].fillna(prior_surplus)
    return x

def train(records, provider_id):
    df=pd.DataFrame(records)
    if len(df)<10: return {'trained':False,'reason':'At least 10 historical records are required; using a labelled recent-average fallback.'}
    df=_features(df); df=df.dropna(subset=['consumed'])
    if len(df)<10: return {'trained':False,'reason':'Not enough usable records after cleaning.'}
    split=max(5,int(len(df)*0.8)); split=min(split,len(df)-2)
    tr,te=df.iloc[:split],df.iloc[split:]
    evaluation_model=RandomForestRegressor(n_estimators=250,min_samples_leaf=2,random_state=42,n_jobs=-1)
    evaluation_model.fit(tr[FEATURES],tr.consumed)
    pred=np.maximum(0,evaluation_model.predict(te[FEATURES])); base=np.maximum(0,te['rolling_mean_7'].to_numpy())
    metrics={'mae':float(mean_absolute_error(te.consumed,pred)), 'rmse':float(np.sqrt(mean_squared_error(te.consumed,pred))),
             'r2':float(r2_score(te.consumed,pred)) if len(te)>1 else None,
             'baseline_mae':float(mean_absolute_error(te.consumed,base)), 'training_records':len(tr),'testing_records':len(te)}
    # Evaluate on a chronological holdout, then persist a production model refit on all history.
    model=RandomForestRegressor(n_estimators=250,min_samples_leaf=2,random_state=42,n_jobs=-1)
    model.fit(df[FEATURES],df.consumed)
    version='rf-'+date.today().isoformat()+'-'+str(provider_id)
    path=MODEL_DIR/f'provider_{provider_id}.joblib'; fingerprint=_fingerprint(records)
    joblib.dump({'model':model,'version':version,'features':FEATURES,'fingerprint':fingerprint},path)
    importance=sorted([{'feature':name,'importance':float(value)} for name,value in zip(FEATURES,model.feature_importances_)],key=lambda x:x['importance'],reverse=True)
    return {'trained':True,'version':version,'model_path':str(path),'metrics':metrics,'feature_importance':importance,'reason':'Random Forest evaluated on the newest 20% of records; no random shuffle.'}

def predict(records, provider_id, target_date, meal_type, food_category, event_indicator=False, holiday_indicator=False):
    df=pd.DataFrame(records)
    if df.empty or not {'meal_type','food_category','consumed'}.issubset(df.columns):
        return 0.0,'Fallback recent average','Insufficient historical data; no matching demand records are available. Add historical records before relying on a forecast.'
    matching=df[(df.meal_type==meal_type)&(df.food_category==food_category)].copy()
    if len(matching)<10:
        vals=matching.sort_values('record_date').tail(7).consumed.tolist()
        if not vals: vals=df[df.meal_type==meal_type].sort_values('record_date').tail(7).consumed.tolist()
        if not vals: vals=df.sort_values('record_date').tail(7).consumed.tolist()
        demand=float(np.mean(vals)) if vals else 0.0
        return max(0,demand),'Fallback recent average','Insufficient matching history for a trained Random Forest. The estimate is a clearly labelled recent-average baseline.'
    model_path=MODEL_DIR/f'provider_{provider_id}.joblib'
    fingerprint=_fingerprint(records)
    if model_path.exists():
        try:
            if joblib.load(model_path).get('fingerprint')!=fingerprint: model_path.unlink()
        except Exception: model_path.unlink(missing_ok=True)
    if not model_path.exists():
        trained=train(records,provider_id)
        if not trained.get('trained'):
            return float(matching.consumed.tail(7).mean()),'Fallback recent average',trained['reason']
    bundle=joblib.load(model_path); f=_features(matching)
    last=f.iloc[-1]; d=pd.Timestamp(target_date)
    row={'weekday':d.weekday(),'meal_code':MEALS.get(meal_type,1),'category_code':int({v:i for i,v in enumerate(sorted(df.food_category.fillna('General').astype(str).unique()))}.get(food_category,0)),
         'event_indicator':int(bool(event_indicator)),'holiday_indicator':int(bool(holiday_indicator)),'lag_1':float(matching.consumed.iloc[-1]),
         'lag_7':float(matching.consumed.iloc[-7]) if len(matching)>=7 else float(matching.consumed.mean()),
         'lag_prepared':float(matching.prepared.iloc[-1]),'lag_surplus':float(matching.surplus.iloc[-1]),
         'rolling_mean_7':float(matching.consumed.tail(7).mean())}
    top=sorted(zip(FEATURES,bundle['model'].feature_importances_),key=lambda z:z[1],reverse=True)[:3]
    drivers=', '.join(name.replace('_',' ') for name,score in top if score>0) or 'historical demand patterns'
    return (max(0,float(bundle['model'].predict(pd.DataFrame([row])[FEATURES])[0])), 'Random Forest',
      f"Forecast uses {len(matching)} matching historical {meal_type.lower()} records, weekday and recent demand patterns. Influential model features include {drivers}. Feature importance describes model reliance, not causation. This is an estimate, not a guarantee.")

def scenario(demand, planned, buffer_percent=3, low=5, medium=15, reference_planned=None):
    planned=max(0,int(planned)); demand=max(0,float(demand)); surplus=max(0,planned-demand)
    waste=100*surplus/planned if planned else 0
    recommended=int(np.ceil(demand*(1+buffer_percent/100)))
    risk='Low' if waste<low else ('Medium' if waste<medium else 'High')
    baseline_surplus=max(0,int(reference_planned if reference_planned is not None else planned)-demand)
    reduction=max(0,baseline_surplus-surplus)
    recommendation=('Preparation is below predicted demand; review service coverage.' if planned<demand else ('Within the configured preparation buffer.' if planned<=recommended else 'Consider reducing preparation toward the recommended quantity.'))
    return {'predicted_demand':round(demand,1),'planned_preparation':planned,'estimated_surplus':int(np.ceil(surplus)),'potential_surplus_reduction':round(reduction,1),'recommendation':recommendation,
            'recommended_preparation':recommended,'waste_percentage':round(waste,2),'risk_level':risk,
            'demand_coverage':round(100*planned/demand,1) if demand else 0}
