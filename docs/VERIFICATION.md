# Verification plan — increment 3.1

| ID | Requirement | Automated coverage | Remaining validation |
|---|---|---|---|
| SMX-31-001 | Registry rejects duplicate ID/version | Unit test | Package signature governance |
| SMX-31-002 | Canonical config digests stable | Unit test | Cross-runtime canonicalization |
| SMX-31-003 | Invalid assessment status combinations rejected | Unit test | Full evidence schema catalog |
| SMX-31-004 | Idempotent submission | SQLite isolated test | PostgreSQL concurrency test |
| SMX-31-005 | Changed content with same idempotency key rejected | SQLite isolated test | Concurrent submissions race test |
| SMX-31-006 | Result and provenance persisted | SQLite isolated test | PostgreSQL crash/recovery test |
| SMX-31-007 | API requires authorization gate | API test | Host RBAC integration |
| SMX-31-008 | Concurrent claim uses SKIP LOCKED | Code review | PostgreSQL integration test |
| SMX-31-009 | Workers recover after interruption | Design only | Failure injection |
| SMX-31-010 | Results immutable | API design | DB-level privilege/trigger enforcement |

Run `pytest -q` after `pip install -e '.[test]'`. Do not treat passing unit tests as clinical validation or production security approval.
