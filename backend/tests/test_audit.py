# tests/test_audit.py
import pytest
from httpx import AsyncClient
from fastapi import status

@pytest.fixture
async def sys_admin_auth_headers(async_client: AsyncClient):
    """Register and login a system admin user to get auth headers."""
    email = "sysadmin_audit_test@spacemedx.com"
    password = "SecurePassword123!"
    await async_client.post("/api/v1/auth/register", json={
        "email": email,
        "password": password,
        "full_name": "System Administrator",
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
    email = "astronaut_audit_test@spacemedx.com"
    password = "SecurePassword123!"
    await async_client.post("/api/v1/auth/register", json={
        "email": email,
        "password": password,
        "full_name": "Test Astronaut Audit",
        "role": "astronaut"
    })
    response = await async_client.post("/api/v1/auth/login", json={
        "email": email,
        "password": password
    })
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}

@pytest.mark.asyncio
async def test_get_audit_logs_as_sys_admin(async_client: AsyncClient, sys_admin_auth_headers):
    """Ensure a system admin can view system-wide audit logs."""
    response = await async_client.get("/api/v1/audit/logs", headers=sys_admin_auth_headers)
    
    assert response.status_code == status.HTTP_200_OK
    assert isinstance(response.json(), list)

@pytest.mark.asyncio
async def test_get_audit_logs_forbidden_for_astronaut(async_client: AsyncClient, astronaut_auth_headers):
    """Ensure regular astronauts cannot view audit logs (returns 403 Forbidden)."""
    response = await async_client.get("/api/v1/audit/logs", headers=astronaut_auth_headers)
    
    assert response.status_code == status.HTTP_403_FORBIDDEN
    assert "permission" in response.json()["detail"].lower()