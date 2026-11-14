# tests/test_ingestion.py
import pytest
from httpx import AsyncClient
from fastapi import status

@pytest.fixture
async def mission_control_auth_headers(async_client: AsyncClient):
    """Register and login a mission control user to get auth headers."""
    email = "control_ingest_test@spacemedx.com"
    password = "SecurePassword123!"
    await async_client.post("/api/v1/auth/register", json={
        "email": email,
        "password": password,
        "full_name": "Mission Controller Ingest",
        "role": "mission_control"
    })
    response = await async_client.post("/api/v1/auth/login", json={
        "email": email,
        "password": password
    })
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}

@pytest.fixture
async def astronaut_auth_headers(async_client: AsyncClient):
    """Register and login an astronaut user to get auth headers."""
    email = "astronaut_ingest_test@spacemedx.com"
    password = "SecurePassword123!"
    await async_client.post("/api/v1/auth/register", json={
        "email": email,
        "password": password,
        "full_name": "Test Astronaut Ingest",
        "role": "astronaut"
    })
    response = await async_client.post("/api/v1/auth/login", json={
        "email": email,
        "password": password
    })
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}

@pytest.mark.asyncio
async def test_ingest_batch_success(async_client: AsyncClient, mission_control_auth_headers):
    """Ensure mission control can successfully ingest a telemetry batch."""
    payload = {
        "batch_reference": "BATCH-2026-001",
        "source_device_id": "SN-WEAR-999",
        "format": "json",
        "payload_data": [
            {"timestamp": "2026-06-06T12:00:00Z", "heart_rate": 72},
            {"timestamp": "2026-06-06T12:01:00Z", "heart_rate": 75}
        ]
    }
    
    response = await async_client.post("/api/v1/ingestion/batch", json=payload, headers=mission_control_auth_headers)
    
    assert response.status_code == status.HTTP_201_CREATED
    data = response.json()
    assert data["batch_reference"] == payload["batch_reference"]
    assert data["source_device_id"] == payload["source_device_id"]
    assert data["records_processed"] == 2
    assert data["status"] == "success"
    assert "id" in data

@pytest.mark.asyncio
async def test_ingest_batch_forbidden_for_astronaut(async_client: AsyncClient, astronaut_auth_headers):
    """Ensure regular astronauts cannot ingest batch data (returns 403 Forbidden)."""
    payload = {
        "batch_reference": "BATCH-2026-002",
        "source_device_id": "SN-WEAR-888",
        "format": "json",
        "payload_data": [{"sample": 1}]
    }
    
    response = await async_client.post("/api/v1/ingestion/batch", json=payload, headers=astronaut_auth_headers)
    
    assert response.status_code == status.HTTP_403_FORBIDDEN
    assert "permission" in response.json()["detail"].lower()