# tests/test_environment.py
import pytest

@pytest.mark.asyncio
async def test_ingest_environmental_telemetry_as_mission_control(async_client):
    """Test that mission control or medical officers can ingest and filter environmental telemetry."""
    
    # 1. Register a mission control user
    user_data = {
        "email": "control.lead@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "Commander Control",
        "role": "mission_control"
    }
    await async_client.post("/api/v1/auth/register", json=user_data)

    # 2. Login to get token
    login_res = await async_client.post(
        "/api/v1/auth/login",
        json={"email": user_data["email"], "password": user_data["password"]}
    )
    assert login_res.status_code == 200
    token = login_res.json()["access_token"]

    # 3. Post environmental telemetry
    telemetry_payload = {
        "location_type": "planet",
        "location_identifier": "Artemis Base Alpha",
        "metric_type": "co2_level",
        "value": 450.5,
        "unit": "ppm",
        "alert_level": "warning",
        "notes": "Slight elevation in atmospheric CO2 scrubber efficiency dropping."
    }
    response = await async_client.post(
        "/api/v1/environment/telemetry",
        json=telemetry_payload,
        headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 201
    data = response.json()
    assert data["location_identifier"] == "Artemis Base Alpha"
    assert data["value"] == 450.5
    assert data["alert_level"] == "warning"

    # 4. Query telemetry with location_type filter
    get_res = await async_client.get(
        "/api/v1/environment/telemetry?location_type=planet",
        headers={"Authorization": f"Bearer {token}"}
    )
    assert get_res.status_code == 200
    records = get_res.json()
    assert len(records) >= 1
    assert records[0]["location_identifier"] == "Artemis Base Alpha"

@pytest.mark.asyncio
async def test_ingest_environmental_telemetry_forbidden_for_astronaut(async_client):
    """Test that regular astronauts cannot ingest environmental telemetry (returns 403 Forbidden)."""
    
    # 1. Register an astronaut
    astronaut_data = {
        "email": "astro.mike@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "Mike Astronaut",
        "role": "astronaut"
    }
    await async_client.post("/api/v1/auth/register", json=astronaut_data)

    # 2. Login as astronaut
    login_res = await async_client.post(
        "/api/v1/auth/login",
        json={"email": astronaut_data["email"], "password": astronaut_data["password"]}
    )
    assert login_res.status_code == 200
    token = login_res.json()["access_token"]

    # 3. Try to ingest telemetry (should fail with 403)
    telemetry_payload = {
        "location_type": "space",
        "location_identifier": "ISS-Kibo",
        "metric_type": "o2_level",
        "value": 21.0,
        "unit": "%",
        "alert_level": "nominal"
    }
    response = await async_client.post(
        "/api/v1/environment/telemetry",
        json=telemetry_payload,
        headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 403