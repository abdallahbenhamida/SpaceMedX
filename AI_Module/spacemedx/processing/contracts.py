"""Stable external contracts; changes require schema/version review."""
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Literal
from uuid import UUID, uuid4
from pydantic import BaseModel, Field, ConfigDict, model_validator


def utcnow() -> datetime:
    return datetime.now(timezone.utc)

class ExecutionStatus(str, Enum):
    COMPLETED = "COMPLETED"
    SKIPPED = "SKIPPED"
    FAILED = "FAILED"
    TIMED_OUT = "TIMED_OUT"

class FindingStatus(str, Enum):
    NORMAL = "NORMAL"
    ATTENTION = "ATTENTION"
    URGENT_REVIEW = "URGENT_REVIEW"
    INSUFFICIENT_DATA = "INSUFFICIENT_DATA"
    INDETERMINATE = "INDETERMINATE"

class EvidenceType(str, Enum):
    RULE = "RULE"
    STATISTICAL = "STATISTICAL"
    PHYSIOLOGICAL = "PHYSIOLOGICAL"
    ML = "ML"

class InputReference(BaseModel):
    kind: Literal["observation", "feature", "baseline", "asset", "dataset", "synthetic"]
    identifier: str = Field(min_length=1)
    digest: str | None = None
    window_start: datetime | None = None
    window_end: datetime | None = None

class InputManifest(BaseModel):
    schema_version: str = "1.0.0"
    references: list[InputReference] = Field(default_factory=list)
    inline_payload: dict[str, Any] = Field(default_factory=dict)

class ExecutionContext(BaseModel):
    model_config = ConfigDict(extra="forbid")
    run_id: UUID
    job_id: UUID
    subject_id: UUID | None = None
    mission_id: UUID | None = None
    execution_mode: Literal["BATCH", "NEAR_REAL_TIME", "REAL_TIME", "REPLAY", "OFFLINE"] = "BATCH"
    execution_location: Literal["SERVER", "MOBILE", "RESEARCH_WORKER"] = "SERVER"
    configuration: dict[str, Any] = Field(default_factory=dict)
    configuration_digest: str

class QualityProfile(BaseModel):
    status: Literal["VALID", "SUSPECT", "INVALID", "UNKNOWN"] = "UNKNOWN"
    coverage: float | None = Field(default=None, ge=0, le=1)
    flags: list[str] = Field(default_factory=list)

class ProcessingResult(BaseModel):
    schema_version: str = "1.0.0"
    result_id: UUID = Field(default_factory=uuid4)
    processing_run_id: UUID
    algorithm_id: str
    algorithm_version: str
    execution_status: ExecutionStatus
    output_type: str
    output_refs: list[str] = Field(default_factory=list)
    quality_profile: QualityProfile = Field(default_factory=QualityProfile)
    warnings: list[str] = Field(default_factory=list)
    provenance: list[InputReference] = Field(default_factory=list)
    computed_at: datetime = Field(default_factory=utcnow)

class RuleEvidence(BaseModel):
    evidence_schema_version: Literal["1.0.0"] = "1.0.0"
    rule_id: str
    observed_value: float | None = None
    operator: str | None = None
    configured_threshold: float | None = None
    condition_satisfied: bool | None = None
    duration_seconds: float | None = None
    quality_gate: bool | None = None

class StatisticalEvidence(BaseModel):
    evidence_schema_version: Literal["1.0.0"] = "1.0.0"
    statistic_id: str
    estimate: float | None = None
    sample_size: int = Field(ge=0)
    assumptions: list[str] = Field(default_factory=list)

class AssessmentResult(BaseModel):
    schema_version: str = "1.0.0"
    result_id: UUID = Field(default_factory=uuid4)
    processing_run_id: UUID
    method_id: str
    method_version: str
    configuration_digest: str
    subject_id: UUID | None = None
    mission_id: UUID | None = None
    assessment_domain: str
    execution_status: ExecutionStatus
    finding_status: FindingStatus | None = None
    finding_code: str | None = None
    evidence_type: EvidenceType
    evidence: dict[str, Any]
    uncertainty: dict[str, Any] = Field(default_factory=dict)
    quality_summary: QualityProfile = Field(default_factory=QualityProfile)
    applicability: dict[str, Any] = Field(default_factory=dict)
    explanation: dict[str, Any] = Field(default_factory=dict)
    validation_status: Literal["EXPLORATORY", "SOFTWARE_VERIFIED", "RESEARCH_VALIDATED", "CLINICALLY_VALIDATED"] = "EXPLORATORY"
    provenance: list[InputReference] = Field(default_factory=list)
    computed_at: datetime = Field(default_factory=utcnow)

    @model_validator(mode="after")
    def validate_finding(self):
        if self.execution_status != ExecutionStatus.COMPLETED and self.finding_status is not None:
            raise ValueError("Non-completed execution cannot emit a physiological finding")
        if self.execution_status == ExecutionStatus.COMPLETED and self.finding_status is None:
            raise ValueError("Completed assessment requires a finding status")
        if self.evidence_type == EvidenceType.RULE:
            RuleEvidence.model_validate(self.evidence)
        elif self.evidence_type == EvidenceType.STATISTICAL:
            StatisticalEvidence.model_validate(self.evidence)
        return self
