# app/models/mission.py
import uuid
from datetime import datetime, timezone
from sqlalchemy import String, DateTime, Enum as SQLEnum, Boolean
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base
from app.enums.mission import MissionType, MissionStatus

class Mission(Base):
    __tablename__ = "missions"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4, index=True)
    name: Mapped[str] = mapped_column(String(150), unique=True, nullable=False)
    code: Mapped[str] = mapped_column(String(50), unique=True, index=True, nullable=False)
    
    mission_type: Mapped[MissionType] = mapped_column(
        SQLEnum(MissionType, name="mission_type_enum"),
        default=MissionType.LUNAR,
        nullable=False
    )
    status: Mapped[MissionStatus] = mapped_column(
        SQLEnum(MissionStatus, name="mission_status_enum"),
        default=MissionStatus.PLANNED,
        nullable=False
    )
    
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc), nullable=False)