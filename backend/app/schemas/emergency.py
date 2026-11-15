# app/schemas/emergency.py
import uuid
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field
from app.enums.emergency import EmergencyGrantStatus

class EmergencyGrantCreate(BaseModel):
    grantee_id: uuid.UUID
    reason: str = Field(..., min_length=5, max_length=500)
    duration_hours: int = Field(default=4, ge=1, le=72)

class EmergencyGrantResponse(BaseModel):
    id: uuid.UUID
    grantor_id: uuid.UUID
    grantee_id: uuid.UUID
    reason: str
    status: EmergencyGrantStatus
    expires_at: datetime
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)