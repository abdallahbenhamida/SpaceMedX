from uuid import uuid4
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from spacemedx.app import create_app, registry
from spacemedx.processing.database import Store, Job, Run, Result, ProvenanceEdge
from spacemedx.processing.service import ProcessingService, JobConflict
from spacemedx.processing.contracts import InputManifest, InputReference

@pytest.fixture
def store(tmp_path):
    s = Store(f"sqlite:///{tmp_path / 'test.db'}")
    s.create_schema()
    yield s
    s.engine.dispose()

def manifest():
    return InputManifest(references=[InputReference(kind="synthetic", identifier="test-001")])

def test_submit_idempotent_and_conflict(store):
    svc = ProcessingService(store, registry)
    kw = dict(algorithm_id="SMX-DEMO-001", version="1.0.0", manifest=manifest(),
              configuration={}, scope_id="org-1", idempotency_key="key-1")
    first = svc.submit(**kw)
    assert first == svc.submit(**kw)
    with pytest.raises(JobConflict): svc.submit(**{**kw, "configuration":{"x":1}})

def test_worker_execution_and_provenance(store):
    svc = ProcessingService(store, registry)
    jid = svc.submit(algorithm_id="SMX-DEMO-001", version="1.0.0", manifest=manifest(),
                     configuration={}, scope_id="org", idempotency_key="key")
    # SQLite is deliberately not used for concurrent claim; simulate an exclusive lease in this isolated test.
    from datetime import timedelta
    from spacemedx.processing.database import now
    with store.sessions.begin() as db:
        j = db.get(Job, jid)
        j.status, j.lease_owner, j.attempts = "LEASED", "test-worker", 1
        j.lease_expires_at = now() + timedelta(minutes=5)
        db.add(Run(id=str(uuid4()), job_id=jid, attempt_number=1,
                   algorithm_id=j.algorithm_id, algorithm_version=j.algorithm_version,
                   config_digest=j.config_digest, input_digest=j.input_digest, status="RUNNING"))
    result = svc.execute_claimed(jid, "test-worker")
    assert result.output_refs == ["count:1"]
    assert svc.get(jid)["status"] == "COMPLETED"
    with store.sessions() as db:
        assert len(db.scalars(select(Result)).all()) == 1
        assert len(db.scalars(select(ProvenanceEdge)).all()) == 1

def test_api_requires_auth_and_submits(store, monkeypatch):
    monkeypatch.setenv("SPACEMEDX_DEMO_API_KEY", "test-key")
    client = TestClient(create_app(store))
    assert client.get("/api/v1/processing/algorithms").status_code == 401
    headers = {"x-api-key":"test-key"}
    assert client.get("/api/v1/processing/algorithms", headers=headers).status_code == 200
    payload = {"algorithm_id":"SMX-DEMO-001","version":"1.0.0","scope_id":"test",
               "idempotency_key":"abc","configuration":{},"manifest":manifest().model_dump(mode="json")}
    response = client.post("/api/v1/processing/jobs", json=payload, headers=headers)
    assert response.status_code == 202
    jid = response.json()["job_id"]
    assert client.get(f"/api/v1/processing/jobs/{jid}", headers=headers).json()["status"] == "QUEUED"
