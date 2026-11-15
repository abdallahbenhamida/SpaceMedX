# app/models/team.py
import uuid
from datetime import datetime, timezone
from sqlalchemy import String, DateTime, Enum as SQLEnum, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base
from app.enums.team import TeamType, TeamStatus

class Team(Base):
    __tablename__ = "teams"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4, index=True)
    organization_id: Mapped[str] = mapped_column(String(100), index=True, nullable=False)
    mission_id: Mapped[str | None] = mapped_column(String(100), index=True, nullable=True)
    team_name: Mapped[str] = mapped_column(String(150), nullable=False)
    
    team_type: Mapped[TeamType] = mapped_column(
        SQLEnum(TeamType, name="team_type_enum"),
        default=TeamType.CREW,
        nullable=False
    )
    status: Mapped[TeamStatus] = mapped_column(
        SQLEnum(TeamStatus, name="team_status_enum"),
        default=TeamStatus.ACTIVE,
        nullable=False
    )
    
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc), nullable=False)

class TeamMembership(Base):
    __tablename__ = "team_memberships"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4, index=True)
    team_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("teams.id"), index=True, nullable=False)
    subject_id: Mapped[str] = mapped_column(String(100), index=True, nullable=False)
    
    valid_from: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
    valid_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)

class TeamLeadership(Base):
    __tablename__ = "team_leaderships"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4, index=True)
    team_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("teams.id"), index=True, nullable=False)
    user_id: Mapped[str] = mapped_column(String(100), index=True, nullable=False)
    
    valid_from: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
    valid_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)