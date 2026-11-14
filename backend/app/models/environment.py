# app/models/environment.py
import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Float, DateTime, Enum as SQLEnum, Text
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base
from app.enums.environment import MissionLocationType, EnvironmentalMetricType, EnvironmentAlertLevel

class EnvironmentalTelemetry(Base):
    __tablename__ = "environmental_telemetry"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    
    # Location context
    location_type: Mapped[MissionLocationType] = mapped_column(SQLEnum(MissionLocationType), nullable=False)
    location_identifier: Mapped[str] = mapped_column(String(100), nullable=False)  # e.g., "Artemis Base Alpha", "Mars Hab 1"
    
    # Metric details
    metric_type: Mapped[EnvironmentalMetricType] = mapped_column(SQLEnum(EnvironmentalMetricType), nullable=False)
    value: Mapped[float] = mapped_column(Float, nullable=False)
    unit: Mapped[str] = mapped_column(String(20), nullable=False)  # e.g., "ppm", "kPa", "mSv/h"
    
    alert_level: Mapped[EnvironmentAlertLevel] = mapped_column(
        SQLEnum(EnvironmentAlertLevel), 
        default=EnvironmentAlertLevel.NOMINAL, 
        nullable=False
    )
    
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))