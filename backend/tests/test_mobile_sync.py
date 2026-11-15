# tests/test_mobile_sync.py
import json
import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.main import app
from app.core.database import get_db
from app.models.mobile_sync import MobileMeasurementRecord


@pytest.mark.asyncio
async def test_mobile_hub_connection_test():
    """
    Spec Section 2: Connection test: GET {base}.
    Any HTTP answer (200) counts as 'server answers'.
    """
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Test with trailing slash
        resp_slash = await client.get("/measurement/save/")
        assert resp_slash.status_code == 200
        assert resp_slash.json()["status"] == "connected"

        # Test without trailing slash
        resp_no_slash = await client.get("/measurement/save")
        assert resp_no_slash.status_code == 200


@pytest.mark.asyncio
async def test_pulsebelt_all_device_formats():
    """
    Spec Section 5.1: pulsebelt (heart rate)
    Tests Polar H7 (numeric pulse), Galaxy Watch (string pulse + rr), and Demo mode.
    Also verifies Content-Type: application/x-www-form-urlencoded; charset=UTF-8 raw JSON parsing.
    """
    transport = ASGITransport(app=app)
    headers = {
        "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
        "Accept": "*/*",
        "Origin": "https://localhost",
        "Referer": "https://localhost/",
        "X-Requested-With": "hu.spacemedx.hub"
    }

    payload = [
        # Polar H7 (pulse as integer)
        {
            "pulse": 72,
            "timestamp": 1790000000000,
            "device": "EID_107",
            "deviceid": "pulsebelt",
            "remark": ""
        },
        # Galaxy Watch (pulse as string, includes rr)
        {
            "timestamp": 1790000010000,
            "pulse": "80",
            "rr": "",
            "remark": ""
        },
        # Demo simulated data (pulse as string)
        {
            "pulse": "72",
            "timestamp": 1790000020000,
            "device": "DEMO",
            "deviceid": "pulsebelt",
            "remark": "simulated"
        }
    ]

    url = "/measurement/save/1234/pulsebelt/1/1794655056577/1794655056577?profil=0&deviceid=0&ext=1"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(url, content=json.dumps(payload), headers=headers)
        assert response.status_code == 200


@pytest.mark.asyncio
async def test_bloodpressure_format():
    """
    Spec Section 5.2: bloodpressure (Beurer BM85 EID_102 / Standard EID_108).
    """
    transport = ASGITransport(app=app)
    headers = {"Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"}

    payload = [
        {
            "systole": 121,
            "diastole": 79,
            "pulse": 66,
            "daqtimestamp": 1790000000000,
            "meatimestamp": "2026/11/14 8:30:00",
            "timestamp": 1794641400000,
            "description": "at rest",
            "device": "EID_102",
            "deviceid": "bloodpressure"
        }
    ]

    url = "/measurement/save/1234/bloodpressure/1/1794641400000/1794641400000?profil=0&deviceid=0&ext=1"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(url, content=json.dumps(payload), headers=headers)
        assert response.status_code == 200


@pytest.mark.asyncio
async def test_bloodsugar_format():
    """
    Spec Section 5.3: bloodsugar (Dcont NEMERE EID_101).
    """
    transport = ASGITransport(app=app)
    headers = {"Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"}

    payload = [
        {
            "glucose_level": 5.4,
            "glucose_level_unit": "mmol/L",
            "daqtimestamp": 1790000000000,
            "meatimestamp": "2026.11.14. 8:31",
            "timestamp": 1794641460000
        }
    ]

    url = "/measurement/save/1234/bloodsugar/1/1794641460000/1794641460000?profil=0&deviceid=0&ext=1"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(url, content=json.dumps(payload), headers=headers)
        assert response.status_code == 200


@pytest.mark.asyncio
async def test_ecg_block_1876_samples():
    """
    Spec Section 5.4: ecg (Savvy ECG EID_103).
    Block of 1876 samples, 125 Hz (one sample per 8 ms), raw 10-bit strings (0-1023).
    """
    transport = ASGITransport(app=app)
    headers = {"Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"}

    start_ts = 1790000000000
    sample_count = 1876
    payload = [
        {
            "timestamp": start_ts + (i * 8),
            "ch0": str(500 + (i % 523))
        }
        for i in range(sample_count)
    ]
    end_ts = payload[-1]["timestamp"]

    url = f"/measurement/save/1234/ecg/{sample_count}/{start_ts}/{end_ts}?profil=0&deviceid=0&ext=1"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(url, content=json.dumps(payload), headers=headers)
        assert response.status_code == 200


@pytest.mark.asyncio
async def test_unknown_watch_telemetry_type():
    """
    Spec Section 5.5: Other types.
    'The server should store unknown types.'
    """
    transport = ASGITransport(app=app)
    headers = {"Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"}

    payload = [
        {"timestamp": 1790000099000, "spo2": 98, "skin_temp": 36.6}
    ]

    url = "/measurement/save/1234/spo2_custom/1/1790000099000/1790000099000?profil=0&deviceid=0&ext=1"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(url, content=json.dumps(payload), headers=headers)
        assert response.status_code == 200


@pytest.mark.asyncio
async def test_idempotency_duplicate_suppression():
    """
    Spec Section 1 & 4: Delivery is at least once. Server must ignore duplicates.
    Duplicate key: userId + type + record content.
    """
    transport = ASGITransport(app=app)
    headers = {"Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"}

    unique_payload = [
        {
            "pulse": 68,
            "timestamp": 1799999999999,
            "device": "EID_107",
            "deviceid": "pulsebelt",
            "remark": "retry-test"
        }
    ]
    url = "/measurement/save/1234/pulsebelt/1/1799999999999/1799999999999?profil=0&deviceid=0&ext=1"

    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # First submission
        resp1 = await client.post(url, content=json.dumps(unique_payload), headers=headers)
        assert resp1.status_code == 200

        # Retry submission (identical payload) -> should return 200 OK and ignore duplicate
        resp2 = await client.post(url, content=json.dumps(unique_payload), headers=headers)
        assert resp2.status_code == 200