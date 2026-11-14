# tests/test_auth_validation.py
import pytest

@pytest.mark.asyncio
async def test_register_invalid_email(async_client):
    """Test registration fails with an invalid email format."""
    response = await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": "not-an-email",
            "password": "SecurePassword123!",
            "full_name": "Bad Email",
            "role": "astronaut"
        }
    )
    assert response.status_code == 422  # Unprocessable Entity (Pydantic validation error)

@pytest.mark.asyncio
async def test_register_weak_password(async_client):
    """Test registration fails when password is shorter than the minimum length (8 chars)."""
    response = await async_client.post(
        "/api/v1/auth/register",
        json={
            "email": "weak.pass@spacemedx.org",
            "password": "short",
            "full_name": "Weak Pass",
            "role": "astronaut"
        }
    )
    assert response.status_code == 422