import json
from pathlib import Path
import pytest
from spacemedx.datasets.catalog import get_dataset, list_datasets
from spacemedx.datasets.ingest import parse_bidmc_numerics, asset_manifest, write_staging

def test_catalog():
    assert len(list_datasets()) == 13
    assert get_dataset("bidmc").adapter == "bidmc_csv"
    with pytest.raises(KeyError): get_dataset("fake")

def test_bidmc_staging(tmp_path):
    csv = tmp_path / "bidmc_01_Numerics.csv"
    csv.write_text("Time [s],HR,PULSE,RESP,SpO2,Unknown\n0,70,71,16,98,abc\n1,72,73,17,97,abc\n2,broken,74,18,96,abc\n", encoding="utf-8")
    # common header format uses Time [s]; mapping should recognize this variant
    result = parse_bidmc_numerics(csv)
    assert result["counts"] == {"accepted": 11, "rejected": 1}
    assert result["observations"][0]["timestamp_kind"] == "RELATIVE"
    assert all(o["subject_id"] is None for o in result["observations"])
    out = tmp_path / "staging.json"
    write_staging(result, out)
    assert json.loads(out.read_text())["asset"]["sha256"] == asset_manifest("BIDMC", csv)["sha256"]

def test_invalid_time(tmp_path):
    csv = tmp_path / "n.csv"
    csv.write_text("Time [s],HR\nunknown,80\n", encoding="utf-8")
    result = parse_bidmc_numerics(csv)
    assert result["counts"] == {"accepted":0,"rejected":1}

def test_asset_registration(tmp_path):
    path = tmp_path / "sample.edf"
    path.write_bytes(b"sample")
    assert asset_manifest("SLEEP_EDFX",path)["bytes"] == 6
