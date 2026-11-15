# app/schemas/device.py
import uuid
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field
from app.enums.device import DeviceType, DeviceStatus

class DeviceCreate(BaseModel):
    serial_number: str = Field(..., min_length=2, max_length=100)
    name: str = Field(..., min_length=2, max_length=150)
    device_type: DeviceType = DeviceType.WEARABLE
    status: DeviceStatus = DeviceStatus.ONLINE
    firmware_version: str | None = Field(None, max_length=50)

class DeviceResponse(BaseModel):
    id: uuid.UUID
    serial_number: str
    name: str
    device_type: DeviceType
    status: DeviceStatus
    firmware_version: str | None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)