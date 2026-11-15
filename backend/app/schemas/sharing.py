# app/schemas/sharing.py
import uuid
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field
from app.enums.sharing import SharedResourceType, SharingPermission

class ResourceShareCreate(BaseModel):
    resource_type: SharedResourceType
    resource_id: str = Field(..., min_length=1, max_length=100)
    recipient_id: str = Field(..., min_length=1, max_length=100)
    permission: SharingPermission = SharingPermission.READ

class ResourceShareResponse(BaseModel):
    id: uuid.UUID
    resource_type: SharedResourceType
    resource_id: str
    owner_id: str
    recipient_id: str
    permission: SharingPermission
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)