# app/schemas/environment.py
import uuid
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field
from app.enums.environment import MissionLocationType, EnvironmentalMetricType, EnvironmentAlertLevel

class EnvironmentalTelemetryCreate(BaseModel):
    location_type: MissionLocationType
    location_identifier: str = Field(..., min_length=2, max_length=100)
    metric_type: EnvironmentalMetricType
    value: float
    unit: str = Field(..., min_length=1, max_length=20)
    alert_level: EnvironmentAlertLevel = EnvironmentAlertLevel.NOMINAL
    notes: str | None = Field(None, max_length=500)

class EnvironmentalTelemetryResponse(BaseModel):
    id: uuid.UUID
    location_type: MissionLocationType
    location_identifier: str
    metric_type: EnvironmentalMetricType
    value: float
    unit: str
    alert_level: EnvironmentAlertLevel
    notes: str | None
    recorded_at: datetime

    model_config = ConfigDict(from_attributes=True)