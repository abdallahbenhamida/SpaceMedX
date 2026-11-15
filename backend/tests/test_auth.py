# tests/test_auth.py
import pytest

@pytest.mark.asyncio
async def test_register_user(async_client):
    """Test successful user registration with valid role and payload."""
    response = await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": "alex.mercer@spacemedx.org",
            "password": "SecurePassword123!",
            "full_name": "Alex Mercer",
            "role": "astronaut"
        }
    )
    assert response.status_code == 201
    data = response.json()
    assert data["email"] == "alex.mercer@spacemedx.org"
    assert data["full_name"] == "Alex Mercer"
    assert data["role"] == "astronaut"
    assert "id" in data

@pytest.mark.asyncio
async def test_register_duplicate_user(async_client):
    """Test that registering with an existing email returns a 400 error."""
    payload = {
        "email": "duplicate.test@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "Duplicate Test",
        "role": "researcher"
    }
    # First registration
    res1 = await async_client.post("/api/v1/auth/register", json=payload)
    assert res1.status_code == 201

    # Second registration with same email
    res2 = await async_client.post("/api/v1/auth/register", json=payload)
    assert res2.status_code == 400
    assert "already exists" in res2.json()["detail"]

@pytest.mark.asyncio
async def test_login_success(async_client):
    """Test successful login returns a bearer access token."""
    payload = {
        "email": "login.test@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "Login Test User",
        "role": "medical_officer"
    }
    # Ensure user is registered
    await async_client.post("/api/v1/auth/register", json=payload)

    # Attempt login
    response = await async_client.post(
        "/api/v1/auth/login",
        json={
            "email": "login.test@spacemedx.org",
            "password": "SecurePassword123!"
        }
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"

@pytest.mark.asyncio
async def test_login_invalid_credentials(async_client):
    """Test that logging in with incorrect credentials returns 401 Unauthorized."""
    response = await async_client.post(
        "/api/v1/auth/login",
        json={
            "email": "nonexistent@spacemedx.org",
            "password": "WrongPassword!"
        }
    )
    assert response.status_code == 401
    assert "Incorrect email or password" in response.json()["detail"]