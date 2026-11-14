# tests/test_teams.py
import pytest
from httpx import AsyncClient
from fastapi import status

@pytest.fixture
async def org_admin_auth_headers(async_client: AsyncClient):
    """Register and login an organization admin user to get auth headers."""
    email = "orgadmin_team_test@spacemedx.com"
    password = "SecurePassword123!"
    await async_client.post("/api/v1/auth/register", json={
        "email": email,
        "password": password,
        "full_name": "Org Administrator",
        "role": "org_admin"
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
    email = "astronaut_team_test@spacemedx.com"
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
async def test_create_team_success(async_client: AsyncClient, org_admin_auth_headers):
    """Ensure an organization admin can successfully create a team."""
    payload = {
        "organization_id": "org-uuid-123",
        "team_name": "Alpha Squad",
        "team_type": "squad",
        "status": "active"
    }
    
    response = await async_client.post("/api/v1/teams", json=payload, headers=org_admin_auth_headers)
    
    assert response.status_code == status.HTTP_201_CREATED
    data = response.json()
    assert data["team_name"] == payload["team_name"]
    assert data["team_type"] == payload["team_type"]
    assert "id" in data

@pytest.mark.asyncio
async def test_create_team_forbidden_for_astronaut(async_client: AsyncClient, astronaut_auth_headers):
    """Ensure regular astronauts cannot create teams (returns 403 Forbidden)."""
    payload = {
        "organization_id": "org-uuid-123",
        "team_name": "Unauthorized Squad",
        "team_type": "squad"
    }
    
    response = await async_client.post("/api/v1/teams", json=payload, headers=astronaut_auth_headers)
    
    assert response.status_code == status.HTTP_403_FORBIDDEN
    assert "permission" in response.json()["detail"].lower()