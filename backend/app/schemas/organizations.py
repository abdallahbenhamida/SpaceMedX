# app/schemas/organizations.py
from uuid import UUID
from datetime import datetime
from pydantic import BaseModel, Field, ConfigDict
from app.enums.user import UserRole
from app.enums.organizations import OrganizationStatus

class OrganizationCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=100)
    code: str = Field(..., min_length=2, max_length=20)
    description: str | None = Field(None, max_length=500)

class OrganizationUpdate(BaseModel):
    name: str | None = Field(None, min_length=2, max_length=100)
    description: str | None = Field(None, max_length=500)
    status: OrganizationStatus | None = None

class OrganizationResponse(BaseModel):
    id: UUID
    name: str
    code: str
    description: str | None
    status: OrganizationStatus
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

class OrganizationMembershipCreate(BaseModel):
    user_id: UUID
    role_in_org: UserRole = UserRole.RESEARCHER

class OrganizationMembershipResponse(BaseModel):
    id: UUID
    user_id: UUID
    organization_id: UUID
    role_in_org: UserRole
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)