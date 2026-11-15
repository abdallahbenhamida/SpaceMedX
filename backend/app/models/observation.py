# app/models/observation.py
import uuid
from datetime import datetime, timezone
from sqlalchemy import String, DateTime, Enum as SQLEnum, Float, Text, Index
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base
from app.enums.observation import ObservationQuality, ObservationSource

class Observation(Base):
    __tablename__ = "observations"

    id: Mapped[uuid.UUID] = mapped_column("observation_id", primary_key=True, default=uuid.uuid4, index=True)
    organization_id: Mapped[uuid.UUID] = mapped_column(index=True, nullable=False)
    mission_id: Mapped[uuid.UUID] = mapped_column(index=True, nullable=False)
    subject_id: Mapped[uuid.UUID] = mapped_column(index=True, nullable=False)
    device_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    parameter_id: Mapped[uuid.UUID] = mapped_column(index=True, nullable=False)
    
    timestamp_utc: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
    
    value_numeric: Mapped[float | None] = mapped_column(Float, nullable=True)
    value_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    unit: Mapped[str] = mapped_column(String(50), nullable=False)
    
    quality_status: Mapped[ObservationQuality] = mapped_column(
        SQLEnum(ObservationQuality, name="observation_quality_enum"),
        default=ObservationQuality.VALID,
        nullable=False
    )
    source_type: Mapped[ObservationSource] = mapped_column(
        SQLEnum(ObservationSource, name="observation_source_enum"),
        default=ObservationSource.WEARABLE,
        nullable=False
    )
    
    sync_batch_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    metadata_info: Mapped[dict | None] = mapped_column("metadata", JSONB, nullable=True)
    
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)

    __table_args__ = (
        Index("ix_observations_subject_param_time", "subject_id", "parameter_id", "timestamp_utc"),
    )