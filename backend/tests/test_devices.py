# tests/test_devices.py
import pytest
from httpx import AsyncClient
from fastapi import status

@pytest.fixture
async def mission_control_auth_headers(async_client: AsyncClient):
    """Register and login a mission control user to get auth headers."""
    email = "control_device_test@spacemedx.com"
    password = "SecurePassword123!"
    await async_client.post("/api/v1/auth/register", json={
        "email": email,
        "password": password,
        "full_name": "Mission Controller",
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
    email = "astronaut_device_test@spacemedx.com"
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
async def test_register_device_success(async_client: AsyncClient, mission_control_auth_headers):
    """Ensure a mission control user can successfully register a device."""
    payload = {
        "serial_number": "SN-WEAR-999",
        "name": "Biometric Smart Band v2",
        "device_type": "wearable",
        "status": "online",
        "firmware_version": "v1.4.2"
    }
    
    response = await async_client.post("/api/v1/devices", json=payload, headers=mission_control_auth_headers)
    
    assert response.status_code == status.HTTP_201_CREATED
    data = response.json()
    assert data["serial_number"] == payload["serial_number"]
    assert data["name"] == payload["name"]
    assert data["device_type"] == payload["device_type"]
    assert data["status"] == payload["status"]
    assert data["firmware_version"] == payload["firmware_version"]
    assert "id" in data

@pytest.mark.asyncio
async def test_register_device_forbidden_for_astronaut(async_client: AsyncClient, astronaut_auth_headers):
    """Ensure regular astronauts cannot register devices (returns 403 Forbidden)."""
    payload = {
        "serial_number": "SN-WEAR-888",
        "name": "Unauthorized Sensor",
        "device_type": "environmental_sensor",
        "status": "online"
    }
    
    response = await async_client.post("/api/v1/devices", json=payload, headers=astronaut_auth_headers)
    
    assert response.status_code == status.HTTP_403_FORBIDDEN
    assert "permission" in response.json()["detail"].lower()