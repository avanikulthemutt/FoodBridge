from fastapi import APIRouter, HTTPException, status
from psycopg.errors import UniqueViolation
from ..database import get_connection
from ..schemas import RegisterInput, LoginInput, AuthResponse, UserOut
from ..security import hash_password, verify_password, create_access_token

router = APIRouter(prefix="/api/auth", tags=["authentication"])

@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def register(payload: RegisterInput):
    if payload.role == "donor" and not (payload.organization_name and payload.donor_type):
        raise HTTPException(422, "organization_name and donor_type are required for providers")
    if payload.role == "ngo" and not (payload.ngo_name and payload.registration_number):
        raise HTTPException(422, "ngo_name and registration_number are required for NGOs")
    try:
        with get_connection() as conn:
            with conn.transaction():
                address = payload.address
                address_id = conn.execute(
                    """INSERT INTO addresses (address_line1,address_line2,landmark,city,state,postal_code,country,latitude,longitude)
                       VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING address_id""",
                    (address.address_line1,address.address_line2,address.landmark,address.city,address.state,
                     address.postal_code,address.country,address.latitude,address.longitude)
                ).fetchone()[0]
                user_id = conn.execute(
                    "INSERT INTO users (email,phone,password_hash,role) VALUES (%s,%s,%s,%s) RETURNING user_id",
                    (payload.email.lower(),payload.phone,hash_password(payload.password),payload.role)
                ).fetchone()[0]
                if payload.role == "donor":
                    conn.execute(
                        """INSERT INTO donors (user_id,organization_name,donor_type,contact_person,contact_phone,address_id)
                           VALUES (%s,%s,%s,%s,%s,%s)""",
                        (user_id,payload.organization_name,payload.donor_type,payload.contact_person,payload.contact_phone,address_id)
                    )
                else:
                    conn.execute(
                        """INSERT INTO ngos (user_id,ngo_name,registration_number,contact_person,contact_phone,address_id,description,people_served_daily)
                           VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
                        (user_id,payload.ngo_name,payload.registration_number,payload.contact_person,payload.contact_phone,
                         address_id,payload.description,payload.people_served_daily)
                    )
        user = UserOut(user_id=user_id,email=payload.email,role=payload.role)
        return AuthResponse(access_token=create_access_token(user_id,payload.role),user=user)
    except UniqueViolation as exc:
        raise HTTPException(409, "Email, phone, or NGO registration number is already registered") from exc

@router.post("/login", response_model=AuthResponse)
def login(payload: LoginInput):
    with get_connection() as conn:
        row = conn.execute(
            "SELECT user_id,email,role,password_hash,is_active FROM users WHERE lower(email)=lower(%s)",
            (payload.email,)
        ).fetchone()
        if not row or not row[4] or not verify_password(payload.password,row[3]):
            raise HTTPException(401, "Invalid email or password")
        conn.execute("UPDATE users SET last_login_at=NOW() WHERE user_id=%s",(row[0],))
    user = UserOut(user_id=row[0],email=row[1],role=row[2])
    return AuthResponse(access_token=create_access_token(row[0],row[2]),user=user)
