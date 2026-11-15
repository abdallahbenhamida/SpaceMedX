"""PostgreSQL-first persistence. SQLite supported for isolated local tests only."""
import os
from datetime import datetime, timezone
from sqlalchemy import create_engine, String, DateTime, Integer, ForeignKey, JSON, Text, UniqueConstraint, Index
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

class Base(DeclarativeBase):
    pass

def now(): return datetime.now(timezone.utc)

class Job(Base):
    __tablename__ = "processing_job"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    algorithm_id: Mapped[str] = mapped_column(String(100), nullable=False)
    algorithm_version: Mapped[str] = mapped_column(String(40), nullable=False)
    scope_id: Mapped[str] = mapped_column(String(80), nullable=False)
    idempotency_key: Mapped[str] = mapped_column(String(120), nullable=False)
    input_manifest: Mapped[dict] = mapped_column(JSON, nullable=False)
    configuration: Mapped[dict] = mapped_column(JSON, nullable=False)
    config_digest: Mapped[str] = mapped_column(String(64), nullable=False)
    input_digest: Mapped[str] = mapped_column(String(64), nullable=False)
    status: Mapped[str] = mapped_column(String(30), default="QUEUED", nullable=False)
    priority: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    lease_owner: Mapped[str | None] = mapped_column(String(100))
    lease_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now, onupdate=now)
    __table_args__ = (UniqueConstraint("scope_id", "idempotency_key", name="uq_job_scope_key"), Index("ix_job_claim", "status", "priority", "created_at"))

class Run(Base):
    __tablename__ = "processing_run"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    job_id: Mapped[str] = mapped_column(ForeignKey("processing_job.id"), nullable=False, index=True)
    attempt_number: Mapped[int] = mapped_column(Integer, nullable=False)
    algorithm_id: Mapped[str] = mapped_column(String(100), nullable=False)
    algorithm_version: Mapped[str] = mapped_column(String(40), nullable=False)
    config_digest: Mapped[str] = mapped_column(String(64), nullable=False)
    input_digest: Mapped[str] = mapped_column(String(64), nullable=False)
    status: Mapped[str] = mapped_column(String(30), nullable=False)
    error_code: Mapped[str | None] = mapped_column(String(100))
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    __table_args__ = (UniqueConstraint("job_id", "attempt_number", name="uq_run_attempt"),)

class Result(Base):
    __tablename__ = "processing_result"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    run_id: Mapped[str] = mapped_column(ForeignKey("processing_run.id"), nullable=False, unique=True)
    job_id: Mapped[str] = mapped_column(ForeignKey("processing_job.id"), nullable=False, unique=True)
    result_type: Mapped[str] = mapped_column(String(30), nullable=False)
    payload: Mapped[dict] = mapped_column(JSON, nullable=False)
    digest: Mapped[str] = mapped_column(String(64), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)

class ProvenanceEdge(Base):
    __tablename__ = "provenance_edge"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    run_id: Mapped[str] = mapped_column(ForeignKey("processing_run.id"), nullable=False, index=True)
    result_id: Mapped[str] = mapped_column(ForeignKey("processing_result.id"), nullable=False)
    input_kind: Mapped[str] = mapped_column(String(50), nullable=False)
    input_identifier: Mapped[str] = mapped_column(String(255), nullable=False)
    input_digest: Mapped[str | None] = mapped_column(String(64))
    input_window: Mapped[dict | None] = mapped_column(JSON)
    relation: Mapped[str] = mapped_column(String(50), default="DERIVED_FROM", nullable=False)

class AuditEvent(Base):
    __tablename__ = "processing_audit_event"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    actor: Mapped[str] = mapped_column(String(100), nullable=False)
    action: Mapped[str] = mapped_column(String(100), nullable=False)
    resource_id: Mapped[str] = mapped_column(String(36), nullable=False)
    details: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)

class Store:
    def __init__(self, url: str | None = None):
        self.url = url or os.environ.get("SPACEMEDX_DATABASE_URL", "postgresql+psycopg://spacemedx:spacemedx@localhost:5432/spacemedx")
        self.engine = create_engine(self.url, pool_pre_ping=True)
        self.sessions = sessionmaker(self.engine, expire_on_commit=False)

    def create_schema(self):
        Base.metadata.create_all(self.engine)
