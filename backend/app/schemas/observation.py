# app/schemas/observation.py
import uuid
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field, AliasChoices
from app.enums.observation import ObservationQuality, ObservationSource

class ObservationCreate(BaseModel):
    organization_id: str
    mission_id: str
    subject_id: str
    device_id: str | None = None
    parameter_id: str
    timestamp_utc: datetime
    value_numeric: float | None = None
    value_text: str | None = Field(None, max_length=1000)
    unit: str = Field(..., min_length=1, max_length=50)
    quality_status: ObservationQuality = ObservationQuality.VALID
    source_type: ObservationSource = ObservationSource.WEARABLE
    sync_batch_id: str | None = None
    metadata_info: dict | None = Field(None, validation_alias=AliasChoices("metadata_info", "metadata"))

    model_config = ConfigDict(populate_by_name=True)

class ObservationResponse(BaseModel):
    id: uuid.UUID = Field(..., alias="observation_id")
    organization_id: uuid.UUID
    mission_id: uuid.UUID
    subject_id: uuid.UUID
    device_id: uuid.UUID | None
    parameter_id: uuid.UUID
    timestamp_utc: datetime
    received_at: datetime
    value_numeric: float | None
    value_text: str | None
    unit: str
    quality_status: ObservationQuality
    source_type: ObservationSource
    sync_batch_id: uuid.UUID | None
    metadata_info: dict | None = Field(None, serialization_alias="metadata")
    created_at: datetime

    model_config = ConfigDict(from_attributes=True, populate_by_name=True)