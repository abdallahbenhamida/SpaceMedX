from uuid import uuid4
import pytest
from pydantic import ValidationError
from spacemedx.processing.contracts import AssessmentResult, ExecutionStatus, FindingStatus, EvidenceType
from spacemedx.processing.config import digest
from spacemedx.processing.registry import Registry
from spacemedx.processing.demo import RecordCountDemo

def test_digest_order_independent():
    assert digest({"a":1,"b":2}) == digest({"b":2,"a":1})

def test_registry_rejects_duplicate():
    r = Registry()
    r.register(RecordCountDemo.manifest, RecordCountDemo)
    with pytest.raises(ValueError): r.register(RecordCountDemo.manifest, RecordCountDemo)

def test_noncompleted_cannot_emit_finding():
    with pytest.raises(ValidationError):
        AssessmentResult(processing_run_id=uuid4(), method_id="x", method_version="1", configuration_digest="a",
            assessment_domain="research", execution_status=ExecutionStatus.FAILED,
            finding_status=FindingStatus.NORMAL, evidence_type=EvidenceType.RULE,
            evidence={"rule_id":"r"})

def test_typed_rule_evidence_required():
    with pytest.raises(ValidationError):
        AssessmentResult(processing_run_id=uuid4(), method_id="x", method_version="1", configuration_digest="a",
            assessment_domain="research", execution_status=ExecutionStatus.COMPLETED,
            finding_status=FindingStatus.INSUFFICIENT_DATA, evidence_type=EvidenceType.RULE,
            evidence={"unrelated":"value"})
