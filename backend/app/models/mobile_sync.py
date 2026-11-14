# app/models/mobile_sync.py
import uuid
from datetime import datetime, timezone
from sqlalchemy import String, DateTime, JSON, Index
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base

class MobileMeasurementRecord(Base):
    __tablename__ = "mobile_measurement_records"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4, index=True)
    user_id: Mapped[str] = mapped_column(String(100), index=True, nullable=False)
    measurement_type: Mapped[str] = mapped_column(String(50), index=True, nullable=False)
    count: Mapped[int] = mapped_column(nullable=False)
    from_timestamp: Mapped[str] = mapped_column(String(50), nullable=False)
    to_timestamp: Mapped[str] = mapped_column(String(50), nullable=False)
    
    record_data: Mapped[dict] = mapped_column(JSON, nullable=False)
    content_hash: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)

    __table_args__ = (
        Index("ix_mobile_user_type_hash", "user_id", "measurement_type", "content_hash"),
    )