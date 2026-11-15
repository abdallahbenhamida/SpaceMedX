# SpaceMedx 3.2.0 — Dataset Integration Source Version

Incremental extension of the approved SpaceMedx 3.1.0 processing foundation.

**New:** 13-source research catalog, local research asset manifests with SHA-256, BIDMC numeric CSV staging parser, CLI, catalog REST endpoints, tests.

**Start here:** [Dataset integration instructions](docs/DATASET_INTEGRATION.md). Original architecture and verification documents remain in `docs/`.

**Existing 3.1 setup:** `pip install -e ".[test]"`; `docker compose up -d postgres`; `python -m spacemedx.init_db`; `pytest -q`; `uvicorn spacemedx.app:app`.

**Important:** NASA/ESA sources currently support catalog and local asset registration, not automatic remote dataset ingestion. This is an initial executable source-code release, not a validated biomedical system.
