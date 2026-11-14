# app/schemas/telemetry.py
import uuid
from datetime import datetime, timezone
from typing import Any
from pydantic import BaseModel, ConfigDict, Field
from app.enums.telemetry import TelemetryChannel, StreamEventType


class TelemetryStreamPacket(BaseModel):
    event: StreamEventType = StreamEventType.TELEMETRY_UPDATE
    channel: TelemetryChannel
    source_id: str = Field(..., min_length=1, max_length=120)
    payload: dict[str, Any]
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class TelemetrySessionResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    channel: TelemetryChannel
    client_identifier: str | None
    is_active: bool
    connected_at: datetime
    disconnected_at: datetime | None

    model_config = ConfigDict(from_attributes=True)