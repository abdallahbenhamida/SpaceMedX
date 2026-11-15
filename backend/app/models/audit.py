import uuid
from datetime import datetime, timezone
from sqlalchemy import String, DateTime, ForeignKey, Enum as SQLEnum, Text
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base
from app.enums.audit import AuditAction

class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    action: Mapped[AuditAction] = mapped_column(SQLEnum(AuditAction), nullable=False)
    resource: Mapped[str] = mapped_column(String(100), nullable=False)  # e.g., "medical_records", "emergency_access_grants"
    details: Mapped[str | None] = mapped_column(Text, nullable=True)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))