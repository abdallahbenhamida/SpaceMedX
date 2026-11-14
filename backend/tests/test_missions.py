# tests/test_missions.py
import pytest
from httpx import AsyncClient
from fastapi import status

@pytest.fixture
async def admin_auth_headers(async_client: AsyncClient):
    """Register and login an admin user to get auth headers."""
    email = "admin_mission_test@spacemedx.com"
    password = "SecurePassword123!"
    await async_client.post("/api/v1/auth/register", json={
        "email": email,
        "password": password,
        "full_name": "Mission Admin",
        "role": "sys_admin"
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
    email = "astronaut_mission_test@spacemedx.com"
    password = "SecurePassword123!"
    await async_client.post("/api/v1/auth/register", json={
        "email": email,
        "password": password,
        "full_name": "Test Astronaut",
        "role": "astronaut"
    })
    response = await async_client.post("/api/v1/auth/login", json={
        "email": email,
        "password": password
    })
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}

@pytest.mark.asyncio
async def test_create_mission_success(async_client: AsyncClient, admin_auth_headers):
    """Ensure an admin user can successfully create a mission."""
    payload = {
        "name": "Artemis III Lunar Outpost",
        "code": "ART-03",
        "mission_type": "lunar",
        "status": "planned",
        "is_active": True
    }
    
    response = await async_client.post("/api/v1/missions", json=payload, headers=admin_auth_headers)
    
    assert response.status_code == status.HTTP_201_CREATED
    data = response.json()
    assert data["name"] == payload["name"]
    assert data["code"] == payload["code"]
    assert data["mission_type"] == payload["mission_type"]
    assert data["status"] == payload["status"]
    assert data["is_active"] is True
    assert "id" in data
    assert "created_at" in data

@pytest.mark.asyncio
async def test_create_mission_duplicate_code(async_client: AsyncClient, admin_auth_headers):
    """Ensure creating a mission with an existing code fails with 400 Bad Request."""
    payload = {
        "name": "Mars Alpha Base",
        "code": "MARS-01",
        "mission_type": "mars",
        "status": "planned",
        "is_active": True
    }
    
    # First creation should succeed
    response_1 = await async_client.post("/api/v1/missions", json=payload, headers=admin_auth_headers)
    assert response_1.status_code == status.HTTP_201_CREATED

    # Second creation with the exact same code should fail
    response_2 = await async_client.post("/api/v1/missions", json=payload, headers=admin_auth_headers)
    assert response_2.status_code == status.HTTP_400_BAD_REQUEST
    assert "already exists" in response_2.json()["detail"]

@pytest.mark.asyncio
async def test_create_mission_forbidden_for_astronaut(async_client: AsyncClient, astronaut_auth_headers):
    """Ensure regular astronauts cannot create missions (returns 403 Forbidden)."""
    payload = {
        "name": "Unauthorized Mission",
        "code": "UN-01",
        "mission_type": "deep_space",
        "status": "planned",
        "is_active": True
    }
    
    response = await async_client.post("/api/v1/missions", json=payload, headers=astronaut_auth_headers)
    
    assert response.status_code == status.HTTP_403_FORBIDDEN
    assert "permission" in response.json()["detail"].lower()