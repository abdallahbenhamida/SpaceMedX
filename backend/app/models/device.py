# app/models/device.py
import uuid
from datetime import datetime, timezone
from sqlalchemy import String, DateTime, Enum as SQLEnum
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base
from app.enums.device import DeviceType, DeviceStatus

class Device(Base):
    __tablename__ = "devices"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4, index=True)
    serial_number: Mapped[str] = mapped_column(String(100), unique=True, index=True, nullable=False)
    name: Mapped[str] = mapped_column(String(150), nullable=False)
    
    device_type: Mapped[DeviceType] = mapped_column(
        SQLEnum(DeviceType, name="device_type_enum"),
        default=DeviceType.WEARABLE,
        nullable=False
    )
    status: Mapped[DeviceStatus] = mapped_column(
        SQLEnum(DeviceStatus, name="device_status_enum"),
        default=DeviceStatus.ONLINE,
        nullable=False
    )
    
    firmware_version: Mapped[str | None] = mapped_column(String(50), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc), nullable=False)