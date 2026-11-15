# SpaceMedx Dataset Source Integration — Increment 3.2.0

## Scope

This **first source-code version** adds 13 discoverable source entries, a local
asset registration adapter for any repository, and a concrete BIDMC numerics
CSV staging adapter. It preserves the original 3.1 PostgreSQL job engine and
contracts. No biomedical algorithm, automatic downloader, restricted-data
access, or clinical validation is implied.

## Commands

```bash
pip install -e ".[test]"
python -m spacemedx.datasets.cli list
python -m spacemedx.datasets.cli register-asset NASA_OSDR /path/to/downloaded.csv --out output/osdr_manifest.json
python -m spacemedx.datasets.cli register-asset NASA_PSI /path/to/experiment.dat --out output/psi_manifest.json
python -m spacemedx.datasets.cli register-asset ESA_BRACE_2023 /path/to/approved_file.csv --out output/brace_manifest.json
python -m spacemedx.datasets.cli bidmc-numerics /path/to/bidmc_01_Numerics.csv --out output/bidmc_staging.json
pytest -q
```

`GET /api/v1/datasets` and `GET /api/v1/datasets/{dataset_id}` expose the catalog
using the existing demo API-key guard. For actual integration, replace that
guard with SpaceMedx host authorization.

## BIDMC CSV conventions

The adapter expects an explicit relative-time column (e.g. `Time [s]`) and
recognized numerical fields (`HR`, `PULSE`, `RESP`, `SpO2`). Source-row and
column identifiers, file SHA-256 and original values are retained. Unmapped
columns are reported, never silently reinterpreted. Relative times are never
converted into fictitious UTC timestamps. Staging observations have no
invented subject IDs. Import into the canonical subject tables is deferred
until consent, scope, subject mapping and schema integration are configured.

## Known limits

- Catalog entries for NASA/ESA sources are **discovery references**, not fully
  implemented remote adapters. Local file asset registration works for each.
- No automated network download, DOI resolution, license enforcement or
  external metadata crawling in this version.
- BIDMC waveform files and Sleep-EDF/CAP EDF recordings can be registered
  as assets, but are not decoded into signals in this increment.
- No PostgreSQL canonical-observation insert from staging output yet; use the
  3.1 job engine independently until the host schema is integrated.
- Source-specific license/access restrictions must be checked before use.
- Tests verify local parsing; no clinical/scientific validation is claimed.
