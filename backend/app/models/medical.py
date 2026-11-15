# app/models/medical.py
import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Float, DateTime, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database import Base

class MedicalRecord(Base):
    __tablename__ = "medical_records"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    
    # Vitals / Telemetry metrics
    heart_rate: Mapped[float] = mapped_column(Float, nullable=False)  # bpm
    blood_pressure_systolic: Mapped[float] = mapped_column(Float, nullable=False)
    blood_pressure_diastolic: Mapped[float] = mapped_column(Float, nullable=False)
    oxygen_saturation: Mapped[float] = mapped_column(Float, nullable=False)  # SpO2 %
    body_temperature: Mapped[float] = mapped_column(Float, nullable=False)  # Celsius
    
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    # Relationship back to User
    user = relationship("User", backref="medical_records")