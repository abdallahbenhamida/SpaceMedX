"""Transactional job orchestration. Never execute algorithms inside request handlers."""
from datetime import timedelta, timezone
from uuid import UUID, uuid4
from sqlalchemy import select, or_
from sqlalchemy.exc import IntegrityError
from .contracts import InputManifest, ExecutionContext, ProcessingResult, AssessmentResult
from .config import digest
from .database import Store, Job, Run, Result, ProvenanceEdge, AuditEvent, now
from .registry import Registry

class JobConflict(ValueError): pass

def lease_expired(value):
    if value is None:
        return True
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)  # SQLite test backend strips timezone
    return value < now()


class ProcessingService:
    def __init__(self, store: Store, registry: Registry):
        self.store, self.registry = store, registry

    def submit(self, *, algorithm_id: str, version: str, manifest: InputManifest,
               configuration: dict, scope_id: str, idempotency_key: str, actor: str = "system") -> str:
        self.registry.create(algorithm_id, version)
        cfg_digest = digest(configuration)
        input_digest = digest(manifest.model_dump(mode="json"))
        with self.store.sessions.begin() as db:
            previous = db.scalar(select(Job).where(Job.scope_id == scope_id, Job.idempotency_key == idempotency_key))
            if previous:
                if (previous.algorithm_id, previous.algorithm_version, previous.config_digest, previous.input_digest) != (algorithm_id, version, cfg_digest, input_digest):
                    raise JobConflict("Idempotency key reused with different content")
                return previous.id
            jid = str(uuid4())
            db.add(Job(id=jid, algorithm_id=algorithm_id, algorithm_version=version, scope_id=scope_id,
                       idempotency_key=idempotency_key, input_manifest=manifest.model_dump(mode="json"),
                       configuration=configuration, config_digest=cfg_digest, input_digest=input_digest))
            db.add(AuditEvent(id=str(uuid4()), actor=actor, action="JOB_SUBMITTED", resource_id=jid, details={"algorithm": algorithm_id}))
            return jid

    def claim(self, worker_id: str, lease_seconds: int = 120, max_attempts: int = 3) -> str | None:
        if self.store.engine.dialect.name != "postgresql":
            raise RuntimeError("Concurrent job claiming requires PostgreSQL")
        with self.store.sessions.begin() as db:
            candidate = db.scalar(select(Job).where(or_(Job.status == "QUEUED",
                (Job.status == "LEASED") & (Job.lease_expires_at < now())))
                .where(Job.attempts < max_attempts)
                .order_by(Job.priority.desc(), Job.created_at.asc())
                .with_for_update(skip_locked=True).limit(1))
            if candidate is None:
                return None
            candidate.status = "LEASED"
            candidate.attempts += 1
            candidate.lease_owner = worker_id
            candidate.lease_expires_at = now() + timedelta(seconds=lease_seconds)
            db.add(Run(id=str(uuid4()), job_id=candidate.id, attempt_number=candidate.attempts,
                       algorithm_id=candidate.algorithm_id, algorithm_version=candidate.algorithm_version,
                       config_digest=candidate.config_digest, input_digest=candidate.input_digest, status="RUNNING"))
            return candidate.id

    def execute_claimed(self, job_id: str, worker_id: str):
        with self.store.sessions() as db:
            job = db.get(Job, job_id)
            if not job or job.status != "LEASED" or job.lease_owner != worker_id or lease_expired(job.lease_expires_at):
                raise ValueError("Job lease not owned by worker")
            run = db.scalar(select(Run).where(Run.job_id == job_id, Run.attempt_number == job.attempts))
            run_id = run.id
            algorithm_id, version = job.algorithm_id, job.algorithm_version
            config, manifest_dict = job.configuration, job.input_manifest
            cfg_digest = job.config_digest
        try:
            manifest = InputManifest.model_validate(manifest_dict)
            algo = self.registry.create(algorithm_id, version)
            if "BATCH" not in algo.manifest.supported_modes:
                raise ValueError("Algorithm does not support batch execution")
            context = ExecutionContext(run_id=UUID(run_id), job_id=UUID(job_id),
                                       configuration=config, configuration_digest=cfg_digest)
            result = algo.execute(manifest, context)
            if not isinstance(result, (ProcessingResult, AssessmentResult)):
                raise TypeError("Algorithm returned invalid result type")
            if result.processing_run_id != UUID(run_id):
                raise ValueError("Algorithm result run ID mismatch")
            if isinstance(result, ProcessingResult):
                if (result.algorithm_id, result.algorithm_version) != (algorithm_id, version):
                    raise ValueError("Algorithm identity mismatch")
            else:
                if (result.method_id, result.method_version, result.configuration_digest) != (algorithm_id, version, cfg_digest):
                    raise ValueError("Assessment method identity/configuration mismatch")
            payload = result.model_dump(mode="json")
            with self.store.sessions.begin() as db:
                job = db.get(Job, job_id, with_for_update=True)
                if job.lease_owner != worker_id or job.status != "LEASED" or lease_expired(job.lease_expires_at):
                    raise RuntimeError("Lease lost before persistence")
                if db.scalar(select(Result).where(Result.job_id == job_id)):
                    raise RuntimeError("Result already persisted")
                db.add(Result(id=str(result.result_id), job_id=job_id, run_id=run_id,
                              result_type="ASSESSMENT" if isinstance(result, AssessmentResult) else "PROCESSING",
                              payload=payload, digest=digest(payload)))
                for ref in result.provenance:
                    db.add(ProvenanceEdge(id=str(uuid4()), run_id=run_id, result_id=str(result.result_id),
                        input_kind=ref.kind, input_identifier=ref.identifier, input_digest=ref.digest,
                        input_window={"start":ref.window_start.isoformat() if ref.window_start else None,
                                      "end":ref.window_end.isoformat() if ref.window_end else None}))
                run = db.get(Run, run_id)
                run.status, run.finished_at = "COMPLETED", now()
                job.status, job.lease_owner, job.lease_expires_at = "COMPLETED", None, None
                db.add(AuditEvent(id=str(uuid4()), actor=worker_id, action="JOB_COMPLETED", resource_id=job_id, details={"run_id":run_id}))
            return result
        except Exception as exc:
            with self.store.sessions.begin() as db:
                job = db.get(Job, job_id, with_for_update=True)
                if job.lease_owner == worker_id and job.status == "LEASED":
                    run = db.get(Run, run_id)
                    run.status, run.finished_at, run.error_code = "FAILED", now(), type(exc).__name__
                    job.status = "QUEUED" if job.attempts < 3 else "FAILED"
                    job.lease_owner, job.lease_expires_at = None, None
                    db.add(AuditEvent(id=str(uuid4()), actor=worker_id, action="JOB_ATTEMPT_FAILED", resource_id=job_id,
                                      details={"run_id":run_id, "error_type":type(exc).__name__}))
            raise

    def get(self, job_id: str) -> dict | None:
        with self.store.sessions() as db:
            job = db.get(Job, job_id)
            if job is None: return None
            result = db.scalar(select(Result).where(Result.job_id == job_id))
            return {"job_id":job.id, "status":job.status, "attempts":job.attempts,
                    "result":result.payload if result else None}
