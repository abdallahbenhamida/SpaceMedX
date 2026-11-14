# app/schemas/medical.py
import uuid
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field

class MedicalRecordCreate(BaseModel):
    user_id: uuid.UUID
    heart_rate: float = Field(..., gt=30, lt=250, description="Heart rate in BPM")
    blood_pressure_systolic: float = Field(..., gt=50, lt=250)
    blood_pressure_diastolic: float = Field(..., gt=30, lt=150)
    oxygen_saturation: float = Field(..., gt=50, le=100, description="SpO2 percentage")
    body_temperature: float = Field(..., gt=30, lt=45, description="Temperature in Celsius")
    notes: str | None = Field(None, max_length=1000)

class MedicalRecordResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    heart_rate: float
    blood_pressure_systolic: float
    blood_pressure_diastolic: float
    oxygen_saturation: float
    body_temperature: float
    notes: str | None
    recorded_at: datetime

    model_config = ConfigDict(from_attributes=True)