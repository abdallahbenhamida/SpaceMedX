# app/schemas/mission.py
import uuid
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field
from app.enums.mission import MissionType, MissionStatus

class MissionCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=150)
    code: str = Field(..., min_length=2, max_length=50)
    mission_type: MissionType = MissionType.LUNAR
    status: MissionStatus = MissionStatus.PLANNED
    is_active: bool = True

class MissionResponse(BaseModel):
    id: uuid.UUID
    name: str
    code: str
    mission_type: MissionType
    status: MissionStatus
    is_active: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)