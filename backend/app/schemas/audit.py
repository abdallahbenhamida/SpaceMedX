import uuid
from datetime import datetime
from pydantic import BaseModel, ConfigDict
from app.enums.audit import AuditAction

class AuditLogResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID | None
    action: AuditAction
    resource: str
    details: str | None
    timestamp: datetime

    model_config = ConfigDict(from_attributes=True)