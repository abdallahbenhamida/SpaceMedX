# Architecture decisions — SMX-3.1.0

## Approved Stage 1–3 invariants

1. Modular FastAPI monolith, PostgreSQL-backed jobs and Python workers.
2. Algorithms execute independently and return standardized versioned contracts.
3. Deterministic-first, no AI dependency; no autonomous medical diagnosis or treatment.
4. PostgreSQL stores metadata/results; large signals will use object storage in later increments.
5. Assessment envelope has independently versioned evidence payloads.
6. Provenance uses source references, processing runs, immutable results and explicit edges.
7. FHIR is an API-boundary mapping, not the internal persistence model.
8. Offline rules will use shared declarative definitions with Python/Dart adapters in increment 3.5.
9. Baseline updates require controlled candidate approval; no baseline logic is implemented in 3.1.
10. Stage 4 fusion must not allow ML to suppress deterministic urgent findings.

## Current execution flow

Authenticated development request -> job submission transaction -> PostgreSQL queued job -> worker claims using `FOR UPDATE SKIP LOCKED` -> algorithm registry -> validated result -> transactionally persisted result and provenance edges -> job completion -> API retrieval.

The algorithm receives an immutable logical input manifest and execution context; it does not query SQL. A new plugin must be registered with an ID/version and provide an `execute` method. Its returned run and algorithm identity are checked before persistence.

## Database tables

- `processing_job`: scoped idempotency, input/configuration manifests, lease state.
- `processing_run`: each execution attempt and its input/configuration digests.
- `processing_result`: immutable logical result per job.
- `provenance_edge`: links result to input reference with optional window/digest.
- `processing_audit_event`: append-only application audit events for submission and completion/failure.

## Integration boundaries

Host FastAPI authentication and resource authorization must replace the demonstration key. Host `core` entities (subjects, missions, organizations) are intentionally not recreated. No direct Flutter/React database access. Do not merge into a live backend without reviewing table names, migrations, secrets and authorization.

## Known production gaps

The MVP foundation demonstrates contracts and transaction flow but is not production hardened. Lease renewal, stale-lease terminalization, worker process isolation, cancellation, transactional outbox, structured observability, per-subject authorization and Alembic migrations are next hardening requirements. No clinical validity is claimed.
