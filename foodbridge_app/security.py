"""Small dependency-free password hashing and signed session tokens."""
import os, hmac, hashlib, base64, json, time
SECRET = os.getenv('FOODBRIDGE_SECRET', 'CHANGE-ME-FOODBRIDGE-LOCAL-SECRET')

def hash_password(password: str) -> str:
    salt=os.urandom(16); digest=hashlib.pbkdf2_hmac('sha256',password.encode(),salt,240000)
    return base64.urlsafe_b64encode(salt).decode()+'.'+base64.urlsafe_b64encode(digest).decode()

def verify_password(password: str, stored: str) -> bool:
    try:
        s,d=stored.split('.'); salt=base64.urlsafe_b64decode(s); expected=base64.urlsafe_b64decode(d)
        actual=hashlib.pbkdf2_hmac('sha256',password.encode(),salt,240000)
        return hmac.compare_digest(actual,expected)
    except Exception: return False

def issue_token(user_id:int, role:str, email:str) -> str:
    payload={'sub':user_id,'role':role,'email':email,'exp':int(time.time())+86400}
    raw=base64.urlsafe_b64encode(json.dumps(payload,separators=(',',':')).encode()).decode().rstrip('=')
    sig=base64.urlsafe_b64encode(hmac.new(SECRET.encode(),raw.encode(),hashlib.sha256).digest()).decode().rstrip('=')
    return raw+'.'+sig

def read_token(token:str):
    try:
        raw,sig=token.split('.',1); expected=base64.urlsafe_b64encode(hmac.new(SECRET.encode(),raw.encode(),hashlib.sha256).digest()).decode().rstrip('=')
        if not hmac.compare_digest(sig,expected): return None
        data=json.loads(base64.urlsafe_b64decode(raw+'='*((4-len(raw)%4)%4)))
        return data if data['exp']>time.time() else None
    except Exception: return None
