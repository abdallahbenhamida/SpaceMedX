# app/schemas/subject.py
import uuid
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field
from app.enums.subject import SubjectCategory, SubjectStatus

class SubjectCreate(BaseModel):
    code: str = Field(..., min_length=2, max_length=50)
    name: str = Field(..., min_length=2, max_length=150)
    category: SubjectCategory = SubjectCategory.HUMAN
    status: SubjectStatus = SubjectStatus.ACTIVE
    description: str | None = Field(None, max_length=500)

class SubjectResponse(BaseModel):
    id: uuid.UUID
    code: str
    name: str
    category: SubjectCategory
    status: SubjectStatus
    description: str | None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)