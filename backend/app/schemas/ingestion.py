# app/schemas/ingestion.py
import uuid
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field
from app.enums.ingestion import IngestionFormat, IngestionStatus

class IngestionCreate(BaseModel):
    batch_reference: str = Field(..., min_length=2, max_length=100)
    source_device_id: str = Field(..., min_length=2, max_length=100)
    format: IngestionFormat = IngestionFormat.JSON
    payload_data: list[dict] = Field(..., description="Array of telemetry or sensor records")

class IngestionResponse(BaseModel):
    id: uuid.UUID
    batch_reference: str
    source_device_id: str
    format: IngestionFormat
    status: IngestionStatus
    records_processed: int
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)