"""Offline-first research asset ingestion. Never converts relative time into UTC."""
import csv
import hashlib
import json
import re
from pathlib import Path
from datetime import datetime, timezone
from typing import Any
from .catalog import get_dataset

# BIDMC numerics contain fields such as HR, PULSE, RESP, SpO2; header variants
# are preserved as originals and only unambiguous mappings are normalized.
PARAMETERS = {
    "hr": ("heart_rate", "beats/min"),
    "heart rate": ("heart_rate", "beats/min"),
    "pulse": ("pulse_rate", "beats/min"),
    "resp": ("respiratory_rate", "breaths/min"),
    "respiration rate": ("respiratory_rate", "breaths/min"),
    "spo2": ("oxygen_saturation", "%"),
    "sao2": ("oxygen_saturation", "%"),
}

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def asset_manifest(dataset_id: str, source: Path, *, source_url: str | None = None) -> dict[str, Any]:
    dataset = get_dataset(dataset_id)
    source = Path(source).resolve(strict=True)
    if not source.is_file():
        raise ValueError("Asset must be a regular file")
    return {"schema_version":"1.0.0", "dataset_id":dataset.id, "repository":dataset.agency,
        "source_url":source_url, "source_path":str(source), "filename":source.name,
        "bytes":source.stat().st_size, "sha256":sha256_file(source),
        "registered_at":datetime.now(timezone.utc).isoformat(),
        "access":dataset.access, "original_asset_preserved":True}

def _normalize_header(header: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", header.strip().lower())

def parse_bidmc_numerics(path: Path, *, limit: int | None = None) -> dict[str, Any]:
    """Parse a BIDMC *_Numerics.csv; preserve relative time and source rows.

    No person/mission identifiers are invented. This is a research observation
    staging output, not an authorized human-subject observation insertion.
    """
    path = Path(path)
    manifest = asset_manifest("BIDMC", path)
    if limit is not None and limit < 0:
        raise ValueError("limit must be nonnegative")
    observations, rejected, unmapped = [], [], set()
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        if not reader.fieldnames:
            raise ValueError("CSV header missing")
        columns = {key: _normalize_header(key) for key in reader.fieldnames}
        time_cols = [k for k,v in columns.items() if v in ("time", "times", "seconds", "elapsedtime", "times", "timesec", "times")]
        if not time_cols:
            raise ValueError("BIDMC numerics require an explicit relative-time column")
        time_col = time_cols[0]
        for row_number, row in enumerate(reader, start=2):
            if limit is not None and row_number - 2 >= limit:
                break
            try:
                t = float(row[time_col])
                if not (t >= 0 and t < float("inf")):
                    raise ValueError("invalid relative time")
            except (ValueError, TypeError, OverflowError):
                rejected.append({"row":row_number, "reason":"INVALID_RELATIVE_TIME"})
                continue
            for column, original in row.items():
                if column == time_col or original is None or not original.strip():
                    continue
                mapped = PARAMETERS.get(columns[column])
                if mapped is None:
                    unmapped.add(column)
                    continue
                try:
                    value = float(original)
                    if not (float("-inf") < value < float("inf")):
                        raise ValueError("nonfinite")
                except ValueError:
                    rejected.append({"row":row_number, "column":column, "reason":"INVALID_NUMERIC"})
                    continue
                observations.append({"dataset_id":"BIDMC", "asset_sha256":manifest["sha256"],
                    "source_row":row_number, "source_column":column, "relative_seconds":t,
                    "timestamp_kind":"RELATIVE", "parameter":mapped[0], "value":value,
                    "unit":mapped[1], "original_value":original, "original_unit":mapped[1],
                    "quality_status":"UNKNOWN", "subject_id":None})
    return {"schema_version":"1.0.0", "asset":manifest, "observations":observations,
        "rejected":rejected, "unmapped_columns":sorted(unmapped),
        "counts":{"accepted":len(observations), "rejected":len(rejected)}}

def write_staging(result: dict[str, Any], destination: Path) -> Path:
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Atomic replacement avoids half-written staging outputs.
    tmp = destination.with_suffix(destination.suffix + ".tmp")
    tmp.write_text(json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False), encoding="utf-8")
    tmp.replace(destination)
    return destination
