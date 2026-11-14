# app/models/ingestion.py
import uuid
from datetime import datetime, timezone
from sqlalchemy import String, DateTime, Enum as SQLEnum, Integer, Text
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base
from app.enums.ingestion import IngestionFormat, IngestionStatus

class IngestionLog(Base):
    __tablename__ = "ingestion_logs"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4, index=True)
    batch_reference: Mapped[str] = mapped_column(String(100), unique=True, index=True, nullable=False)
    source_device_id: Mapped[str] = mapped_column(String(100), index=True, nullable=False)
    
    format: Mapped[IngestionFormat] = mapped_column(
        SQLEnum(IngestionFormat, name="ingestion_format_enum"),
        default=IngestionFormat.JSON,
        nullable=False
    )
    status: Mapped[IngestionStatus] = mapped_column(
        SQLEnum(IngestionStatus, name="ingestion_status_enum"),
        default=IngestionStatus.SUCCESS,
        nullable=False
    )
    
    records_processed: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    error_details: Mapped[str | None] = mapped_column(Text, nullable=True)
    
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)