from typing import Literal
from pydantic import BaseModel, EmailStr, Field, ConfigDict

class AddressInput(BaseModel):
    address_line1: str = Field(min_length=3, max_length=255)
    address_line2: str | None = None
    landmark: str | None = None
    city: str = Field(min_length=2, max_length=100)
    state: str = Field(min_length=2, max_length=100)
    postal_code: str = Field(min_length=4, max_length=10)
    country: str = "India"
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)

class RegisterInput(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=72)
    phone: str = Field(min_length=7, max_length=20)
    role: Literal["donor", "ngo"]
    organization_name: str | None = None
    donor_type: Literal["restaurant", "hotel", "college_canteen", "event_organizer", "other"] | None = None
    ngo_name: str | None = None
    registration_number: str | None = None
    contact_person: str = Field(min_length=2, max_length=120)
    contact_phone: str = Field(min_length=7, max_length=20)
    description: str | None = None
    people_served_daily: int | None = Field(default=None, ge=0)
    address: AddressInput

class LoginInput(BaseModel):
    email: EmailStr
    password: str

class UserOut(BaseModel):
    user_id: int
    email: EmailStr
    role: str

class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut
