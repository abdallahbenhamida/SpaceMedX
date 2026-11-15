# app/models/emergency.py
import uuid
from datetime import datetime, timezone
from sqlalchemy import DateTime, ForeignKey, Enum as SQLEnum, Text
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base
from app.enums.emergency import EmergencyGrantStatus

class EmergencyAccessGrant(Base):
    __tablename__ = "emergency_access_grants"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    grantor_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    grantee_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[EmergencyGrantStatus] = mapped_column(
        SQLEnum(EmergencyGrantStatus), 
        default=EmergencyGrantStatus.ACTIVE, 
        nullable=False
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))