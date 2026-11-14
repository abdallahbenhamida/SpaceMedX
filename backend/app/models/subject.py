# app/models/subject.py
import uuid
from datetime import datetime, timezone
from sqlalchemy import String, DateTime, Enum as SQLEnum, Text
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base
from app.enums.subject import SubjectCategory, SubjectStatus

class Subject(Base):
    __tablename__ = "subjects"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4, index=True)
    code: Mapped[str] = mapped_column(String(50), unique=True, index=True, nullable=False)
    name: Mapped[str] = mapped_column(String(150), nullable=False)
    
    category: Mapped[SubjectCategory] = mapped_column(
        SQLEnum(SubjectCategory, name="subject_category_enum"),
        default=SubjectCategory.HUMAN,
        nullable=False
    )
    status: Mapped[SubjectStatus] = mapped_column(
        SQLEnum(SubjectStatus, name="subject_status_enum"),
        default=SubjectStatus.ACTIVE,
        nullable=False
    )
    
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc), nullable=False)