# tests/test_emergency.py
import pytest

@pytest.mark.asyncio
async def test_emergency_grant_lifecycle(async_client):
    """Test issuing, viewing, and revoking an emergency access grant as a medical officer."""
    
    # 1. Register a medical officer (grantor)
    officer_data = {
        "email": "dr.mccoy.emergency@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "Dr. McCoy",
        "role": "medical_officer"
    }
    await async_client.post("/api/v1/auth/register", json=officer_data)

    # 2. Register an astronaut (grantee)
    astronaut_data = {
        "email": "astro.scotty@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "Scotty Astronaut",
        "role": "astronaut"
    }
    reg_res = await async_client.post("/api/v1/auth/register", json=astronaut_data)
    assert reg_res.status_code == 201
    astronaut_id = reg_res.json()["id"]

    # 3. Login as medical officer
    login_res = await async_client.post(
        "/api/v1/auth/login",
        json={"email": officer_data["email"], "password": officer_data["password"]}
    )
    assert login_res.status_code == 200
    token = login_res.json()["access_token"]

    # 4. Issue emergency grant
    grant_payload = {
        "grantee_id": astronaut_id,
        "reason": "Habitat life-support sensor failure requiring emergency data override access.",
        "duration_hours": 12
    }
    response = await async_client.post(
        "/api/v1/emergency/grants",
        json=grant_payload,
        headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 201
    data = response.json()
    assert data["status"] == "active"
    assert data["reason"] == grant_payload["reason"]
    grant_id = data["id"]

    # 5. List emergency grants
    list_res = await async_client.get(
        "/api/v1/emergency/grants",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert list_res.status_code == 200
    grants = list_res.json()
    assert len(grants) >= 1

    # 6. Revoke the emergency grant
    revoke_res = await async_client.patch(
        f"/api/v1/emergency/grants/{grant_id}/revoke",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert revoke_res.status_code == 200
    assert revoke_res.json()["status"] == "revoked"

@pytest.mark.asyncio
async def test_emergency_grant_forbidden_for_astronaut(async_client):
    """Test that regular astronauts cannot issue emergency grants (returns 403 Forbidden)."""
    
    # 1. Register an astronaut
    astronaut_data = {
        "email": "astro.regular@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "Regular Astro",
        "role": "astronaut"
    }
    reg_res = await async_client.post("/api/v1/auth/register", json=astronaut_data)
    assert reg_res.status_code == 201
    astronaut_id = reg_res.json()["id"]

    # 2. Login as astronaut
    login_res = await async_client.post(
        "/api/v1/auth/login",
        json={"email": astronaut_data["email"], "password": astronaut_data["password"]}
    )
    assert login_res.status_code == 200
    token = login_res.json()["access_token"]

    # 3. Attempt to issue emergency grant
    grant_payload = {
        "grantee_id": astronaut_id,
        "reason": "Trying to bypass authorization.",
        "duration_hours": 2
    }
    response = await async_client.post(
        "/api/v1/emergency/grants",
        json=grant_payload,
        headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 403