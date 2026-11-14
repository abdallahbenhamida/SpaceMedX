# tests/test_telemetry_ws.py
import uuid
import pytest
from starlette.websockets import WebSocketDisconnect
from anyio import ClosedResourceError


def test_websocket_environment_broadcast_and_sessions(sync_client):
    """Test real-time telemetry broadcast and session listing via the sync TestClient fixture."""
    client = sync_client

    # 1. Register Mission Control operator
    mc_user = {
        "email": "mc.pure.sync@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "Flight Director",
        "role": "mission_control",
    }
    res = client.post("/api/v1/auth/register", json=mc_user)
    assert res.status_code in (201, 400)

    login_res = client.post(
        "/api/v1/auth/login",
        json={"email": mc_user["email"], "password": mc_user["password"]},
    )
    assert login_res.status_code == 200
    token = login_res.json()["access_token"]

    # 2. Connect two WebSocket clients on the environment channel
    with client.websocket_connect(
        f"/api/v1/telemetry/ws/environment?token={token}&client_id=habitat-sensor-01"
    ) as publisher_ws, client.websocket_connect(
        f"/api/v1/telemetry/ws/environment?token={token}&client_id=console-alpha"
    ) as subscriber_ws:
        # Consume initial 'connected' handshakes
        pub_hello = publisher_ws.receive_json()
        sub_hello = subscriber_ws.receive_json()
        assert pub_hello["event"] == "connected"
        assert sub_hello["event"] == "connected"

        # 3. Publish live CO2 reading
        publisher_ws.send_json({
            "source_id": "hab-module-a",
            "payload": {"metric": "co2_level", "value": 412.5, "unit": "ppm"},
        })

        # 4. Verify subscriber receives the broadcast frame
        received = subscriber_ws.receive_json()
        assert received["event"] == "telemetry_update"
        assert received["channel"] == "environment"
        assert received["source_id"] == "hab-module-a"
        assert received["payload"]["value"] == 412.5

    # 5. Verify sessions can be listed via REST
    sessions_res = client.get(
        "/api/v1/telemetry/sessions?active_only=false",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert sessions_res.status_code == 200
    sessions = sessions_res.json()
    assert len(sessions) >= 2


def test_websocket_medical_channel_forbidden_for_guest(sync_client):
    """Test that guest_viewer cannot subscribe to the restricted medical telemetry stream."""
    client = sync_client

    unique_suffix = uuid.uuid4().hex[:8]
    guest_user = {
        "email": f"guest.medical.{unique_suffix}@spacemedx.org",
        "password": "SecurePassword123!",
        "full_name": "Guest Observer",
        "role": "guest_viewer",
    }
    reg_res = client.post("/api/v1/auth/register", json=guest_user)
    assert reg_res.status_code in (201, 400), f"Registration failed: {reg_res.text}"

    login_res = client.post(
        "/api/v1/auth/login",
        json={"email": guest_user["email"], "password": guest_user["password"]},
    )
    assert login_res.status_code == 200, f"Login failed: {login_res.text}"
    token = login_res.json()["access_token"]

    # The server closes with 1008 before/at accept; TestClient surfaces this as
    # WebSocketDisconnect (or ClosedResourceError depending on timing).
    with pytest.raises((WebSocketDisconnect, ClosedResourceError)):
        with client.websocket_connect(f"/api/v1/telemetry/ws/medical?token={token}"):
            pass