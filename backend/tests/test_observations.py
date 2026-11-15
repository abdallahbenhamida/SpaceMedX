# tests/test_observations.py
import pytest
from httpx import AsyncClient
from fastapi import status
import uuid
from datetime import datetime, timezone

@pytest.fixture
async def medical_officer_auth_headers(async_client: AsyncClient):
    """Register and login a medical officer user to get auth headers."""
    email = "medic_obs_test@spacemedx.com"
    password = "SecurePassword123!"
    await async_client.post("/api/v1/auth/register", json={
        "email": email,
        "password": password,
        "full_name": "Medical Officer Obs",
        "role": "medical_officer"
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
    email = "astronaut_obs_test@spacemedx.com"
    password = "SecurePassword123!"
    await async_client.post("/api/v1/auth/register", json={
        "email": email,
        "password": password,
        "full_name": "Test Astronaut Obs",
        "role": "astronaut"
    })
    response = await async_client.post("/api/v1/auth/login", json={
        "email": email,
        "password": password
    })
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}

@pytest.mark.asyncio
async def test_create_observation_success(async_client: AsyncClient, medical_officer_auth_headers):
    """Ensure a medical officer can record a valid observation."""
    payload = {
        "organization_id": str(uuid.uuid4()),
        "mission_id": str(uuid.uuid4()),
        "subject_id": str(uuid.uuid4()),
        "parameter_id": str(uuid.uuid4()),
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "value_numeric": 75.5,
        "unit": "bpm",
        "quality_status": "valid",
        "source_type": "wearable",
        "metadata": {"battery": 98}
    }
    
    response = await async_client.post("/api/v1/observations", json=payload, headers=medical_officer_auth_headers)
    
    assert response.status_code == status.HTTP_201_CREATED
    data = response.json()
    assert data["value_numeric"] == 75.5
    assert data["unit"] == "bpm"
    assert data["quality_status"] == "valid"
    assert "observation_id" in data

@pytest.mark.asyncio
async def test_create_observation_forbidden_for_astronaut(async_client: AsyncClient, astronaut_auth_headers):
    """Ensure regular astronauts cannot create observations directly (returns 403 Forbidden)."""
    payload = {
        "organization_id": str(uuid.uuid4()),
        "mission_id": str(uuid.uuid4()),
        "subject_id": str(uuid.uuid4()),
        "parameter_id": str(uuid.uuid4()),
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "value_numeric": 80.0,
        "unit": "bpm"
    }
    
    response = await async_client.post("/api/v1/observations", json=payload, headers=astronaut_auth_headers)
    
    assert response.status_code == status.HTTP_403_FORBIDDEN
    assert "permission" in response.json()["detail"].lower()