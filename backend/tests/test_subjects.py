# tests/test_subjects.py
import pytest
from httpx import AsyncClient
from fastapi import status

@pytest.fixture
async def researcher_auth_headers(async_client: AsyncClient):
    """Register and login a researcher user to get auth headers."""
    email = "researcher_test@spacemedx.com"
    password = "SecurePassword123!"
    await async_client.post("/api/v1/auth/register", json={
        "email": email,
        "password": password,
        "full_name": "Lead Researcher",
        "role": "researcher"
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
    email = "astronaut_subject_test@spacemedx.com"
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
async def test_create_subject_success(async_client: AsyncClient, researcher_auth_headers):
    """Ensure a researcher user can successfully create a subject."""
    payload = {
        "code": "SUBJ-001",
        "name": "Biological Sample Alpha",
        "category": "biological_sample",
        "status": "active",
        "description": "Exposed to microgravity conditions for 30 days."
    }
    
    response = await async_client.post("/api/v1/subjects", json=payload, headers=researcher_auth_headers)
    
    assert response.status_code == status.HTTP_201_CREATED
    data = response.json()
    assert data["code"] == payload["code"]
    assert data["name"] == payload["name"]
    assert data["category"] == payload["category"]
    assert data["status"] == payload["status"]
    assert data["description"] == payload["description"]
    assert "id" in data

@pytest.mark.asyncio
async def test_create_subject_forbidden_for_astronaut(async_client: AsyncClient, astronaut_auth_headers):
    """Ensure regular astronauts cannot create subjects (returns 403 Forbidden)."""
    payload = {
        "code": "SUBJ-002",
        "name": "Unauthorized Specimen",
        "category": "human",
        "status": "active"
    }
    
    response = await async_client.post("/api/v1/subjects", json=payload, headers=astronaut_auth_headers)
    
    assert response.status_code == status.HTTP_403_FORBIDDEN
    assert "permission" in response.json()["detail"].lower()