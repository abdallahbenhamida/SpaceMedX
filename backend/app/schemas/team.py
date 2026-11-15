# app/schemas/team.py
import uuid
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field
from app.enums.team import TeamType, TeamStatus

class TeamCreate(BaseModel):
    organization_id: str = Field(..., min_length=1, max_length=100)
    mission_id: str | None = Field(None, max_length=100)
    team_name: str = Field(..., min_length=2, max_length=150)
    team_type: TeamType = TeamType.CREW
    status: TeamStatus = TeamStatus.ACTIVE

class TeamResponse(BaseModel):
    id: uuid.UUID
    organization_id: str
    mission_id: str | None
    team_name: str
    team_type: TeamType
    status: TeamStatus
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

class TeamMembershipCreate(BaseModel):
    team_id: uuid.UUID
    subject_id: str = Field(..., min_length=1, max_length=100)
    valid_until: datetime | None = None

class TeamMembershipResponse(BaseModel):
    id: uuid.UUID
    team_id: uuid.UUID
    subject_id: str
    valid_from: datetime
    valid_until: datetime | None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

class TeamLeadershipCreate(BaseModel):
    team_id: uuid.UUID
    user_id: str = Field(..., min_length=1, max_length=100)
    valid_until: datetime | None = None

class TeamLeadershipResponse(BaseModel):
    id: uuid.UUID
    team_id: uuid.UUID
    user_id: str
    valid_from: datetime
    valid_until: datetime | None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)