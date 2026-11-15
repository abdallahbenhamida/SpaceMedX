# app/schemas/user.py
import uuid
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from app.enums.user import UserRole, AccountStatus

class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8)
    full_name: str = Field(..., min_length=2, max_length=150)
    role: UserRole = UserRole.ASTRONAUT

class UserResponse(BaseModel):
    id: uuid.UUID
    email: EmailStr
    full_name: str
    role: UserRole
    status: AccountStatus
    is_verified: bool

    model_config = ConfigDict(from_attributes=True)

class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"

class LoginRequest(BaseModel):
    email: EmailStr
    password: str