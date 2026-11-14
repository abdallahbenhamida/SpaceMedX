# tests/test_users.py
import pytest

@pytest.mark.asyncio
async def test_get_current_user_profile(async_client):
    """Test that a user can access protected endpoints using their JWT access token."""
    user_data = {
        "email": "profile.test@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "Profile Test User",
        "role": "medical_officer"
    }
    
    # 1. Register user
    reg_res = await async_client.post("/api/v1/auth/register", json=user_data)
    assert reg_res.status_code == 201

    # 2. Login to obtain access token
    login_res = await async_client.post(
        "/api/v1/auth/login",
        json={
            "email": user_data["email"],
            "password": user_data["password"]
        }
    )
    assert login_res.status_code == 200
    token_data = login_res.json()
    access_token = token_data["access_token"]

    # 3. Access protected route with Bearer token (Updated path to /api/v1/users/me)
    response = await async_client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {access_token}"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["email"] == user_data["email"]
    assert data["full_name"] == user_data["full_name"]

@pytest.mark.asyncio
async def test_unauthorized_access(async_client):
    """Test that accessing a protected route without a token returns 401 Unauthorized."""
    response = await async_client.get("/api/v1/users/me")
    assert response.status_code == 401