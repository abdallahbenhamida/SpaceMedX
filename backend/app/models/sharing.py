# app/models/sharing.py
import uuid
from datetime import datetime, timezone
from sqlalchemy import String, DateTime, Enum as SQLEnum
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base
from app.enums.sharing import SharedResourceType, SharingPermission

class ResourceShare(Base):
    __tablename__ = "resource_shares"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4, index=True)
    resource_type: Mapped[SharedResourceType] = mapped_column(
        SQLEnum(SharedResourceType, name="shared_resource_type_enum"),
        nullable=False
    )
    resource_id: Mapped[str] = mapped_column(String(100), index=True, nullable=False)
    owner_id: Mapped[str] = mapped_column(String(100), nullable=False)
    recipient_id: Mapped[str] = mapped_column(String(100), index=True, nullable=False)
    
    permission: Mapped[SharingPermission] = mapped_column(
        SQLEnum(SharingPermission, name="sharing_permission_enum"),
        default=SharingPermission.READ,
        nullable=False
    )
    
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)