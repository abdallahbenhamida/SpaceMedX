# tests/test_sharing.py
import pytest
from httpx import AsyncClient
from fastapi import status

@pytest.fixture
async def medical_officer_auth_headers(async_client: AsyncClient):
    """Register and login a medical officer user to get auth headers."""
    email = "medic_share_test@spacemedx.com"
    password = "SecurePassword123!"
    await async_client.post("/api/v1/auth/register", json={
        "email": email,
        "password": password,
        "full_name": "Medical Officer Share",
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
    email = "astronaut_share_test@spacemedx.com"
    password = "SecurePassword123!"
    await async_client.post("/api/v1/auth/register", json={
        "email": email,
        "password": password,
        "full_name": "Test Astronaut Share",
        "role": "astronaut"
    })
    response = await async_client.post("/api/v1/auth/login", json={
        "email": email,
        "password": password
    })
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}

@pytest.mark.asyncio
async def test_create_resource_share_success(async_client: AsyncClient, medical_officer_auth_headers):
    """Ensure a medical officer can successfully share a medical record resource."""
    payload = {
        "resource_type": "medical_record",
        "resource_id": "rec-uuid-1234",
        "recipient_id": "user-uuid-5678",
        "permission": "read"
    }
    
    response = await async_client.post("/api/v1/sharing", json=payload, headers=medical_officer_auth_headers)
    
    assert response.status_code == status.HTTP_201_CREATED
    data = response.json()
    assert data["resource_type"] == payload["resource_type"]
    assert data["resource_id"] == payload["resource_id"]
    assert data["recipient_id"] == payload["recipient_id"]
    assert data["permission"] == payload["permission"]
    assert "id" in data
    assert "owner_id" in data

@pytest.mark.asyncio
async def test_create_resource_share_forbidden_for_astronaut(async_client: AsyncClient, astronaut_auth_headers):
    """Ensure regular astronauts cannot share resources (returns 403 Forbidden)."""
    payload = {
        "resource_type": "telemetry",
        "resource_id": "tel-uuid-9999",
        "recipient_id": "user-uuid-5678",
        "permission": "read"
    }
    
    response = await async_client.post("/api/v1/sharing", json=payload, headers=astronaut_auth_headers)
    
    assert response.status_code == status.HTTP_403_FORBIDDEN
    assert "permission" in response.json()["detail"].lower()