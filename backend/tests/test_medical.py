# tests/test_medical.py
import pytest

@pytest.mark.asyncio
async def test_create_medical_record_as_officer(async_client):
    """Test that a medical officer can successfully log vitals for an astronaut and retrieve them."""
    
    # 1. Register a medical officer
    officer_data = {
        "email": "med.officer@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "Dr. McCoy",
        "role": "medical_officer"
    }
    await async_client.post("/api/v1/auth/register", json=officer_data)

    # 2. Register an astronaut (patient)
    astronaut_data = {
        "email": "astronaut.joe@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "Joe Astronaut",
        "role": "astronaut"
    }
    reg_res = await async_client.post("/api/v1/auth/register", json=astronaut_data)
    assert reg_res.status_code == 201
    astronaut_id = reg_res.json()["id"]

    # 3. Login as medical officer to get token
    login_res = await async_client.post(
        "/api/v1/auth/login",
        json={"email": officer_data["email"], "password": officer_data["password"]}
    )
    assert login_res.status_code == 200
    token = login_res.json()["access_token"]

    # 4. Post medical record as officer
    record_payload = {
        "user_id": astronaut_id,
        "heart_rate": 72.5,
        "blood_pressure_systolic": 120.0,
        "blood_pressure_diastolic": 80.0,
        "oxygen_saturation": 98.0,
        "body_temperature": 36.6,
        "notes": "Vitals stable during pre-flight check."
    }
    response = await async_client.post(
        "/api/v1/medical/records",
        json=record_payload,
        headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 201
    data = response.json()
    assert data["heart_rate"] == 72.5
    assert data["user_id"] == astronaut_id

    # 5. Retrieve medical records for the astronaut
    get_res = await async_client.get(
        f"/api/v1/medical/records/{astronaut_id}",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert get_res.status_code == 200
    records = get_res.json()
    assert len(records) == 1
    assert records[0]["notes"] == "Vitals stable during pre-flight check."

@pytest.mark.asyncio
async def test_create_medical_record_forbidden_for_astronaut(async_client):
    """Test that regular astronauts cannot create/log medical records for others (returns 403 Forbidden)."""
    
    # 1. Register an astronaut
    astronaut_data = {
        "email": "astronaut.jane@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "Jane Astronaut",
        "role": "astronaut"
    }
    reg_res = await async_client.post("/api/v1/auth/register", json=astronaut_data)
    assert reg_res.status_code == 201
    astronaut_id = reg_res.json()["id"]

    # 2. Login as the astronaut
    login_res = await async_client.post(
        "/api/v1/auth/login",
        json={"email": astronaut_data["email"], "password": astronaut_data["password"]}
    )
    assert login_res.status_code == 200
    token = login_res.json()["access_token"]

    # 3. Try to post a medical record (should fail with 403)
    record_payload = {
        "user_id": astronaut_id,
        "heart_rate": 75.0,
        "blood_pressure_systolic": 118.0,
        "blood_pressure_diastolic": 78.0,
        "oxygen_saturation": 99.0,
        "body_temperature": 36.7,
        "notes": "Self-reporting vitals."
    }
    response = await async_client.post(
        "/api/v1/medical/records",
        json=record_payload,
        headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 403