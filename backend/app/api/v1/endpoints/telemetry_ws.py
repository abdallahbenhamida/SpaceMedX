# app/api/v1/endpoints/telemetry_ws.py
from datetime import datetime, timezone
from typing import List
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends, Query, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import ValidationError

from app.core.database import get_db
from app.core.security import decode_access_token, get_current_user
from app.core.ws_manager import telemetry_manager
from app.enums.telemetry import TelemetryChannel, StreamEventType
from app.enums.user import UserRole
from app.models.user import User
from app.models.telemetry_session import TelemetryStreamSession
from app.schemas.telemetry import TelemetryStreamPacket, TelemetrySessionResponse

router = APIRouter(prefix="/telemetry", tags=["Real-Time Telemetry"])

PUBLISH_ROLES = {
    UserRole.SYSTEM_ADMIN,
    UserRole.ORG_ADMIN,
    UserRole.MISSION_ADMIN,
    UserRole.MEDICAL_OFFICER,
    UserRole.MISSION_CONTROL,
    UserRole.ASTRONAUT,
}

RESTRICTED_MEDICAL_ROLES = {
    UserRole.SYSTEM_ADMIN,
    UserRole.ORG_ADMIN,
    UserRole.MISSION_ADMIN,
    UserRole.MEDICAL_OFFICER,
    UserRole.MISSION_CONTROL,
}


async def _authenticate_ws(token: str, db: AsyncSession) -> User | None:
    payload = decode_access_token(token)
    if not payload or "sub" not in payload:
        return None
    return await db.get(User, payload["sub"])


@router.websocket("/ws/{channel}")
async def telemetry_stream(
    websocket: WebSocket,
    channel: TelemetryChannel,
    token: str = Query(...),
    client_id: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
):
    """Real-time bidirectional telemetry stream over WebSockets."""
    user = await _authenticate_ws(token, db)
    if not user:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    if channel in {TelemetryChannel.MEDICAL, TelemetryChannel.ALL} and user.role not in RESTRICTED_MEDICAL_ROLES:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    await telemetry_manager.connect(websocket, channel)

    session_record = TelemetryStreamSession(
        user_id=user.id,
        channel=channel,
        client_identifier=client_id,
        is_active=True,
    )
    db.add(session_record)
    await db.commit()
    await db.refresh(session_record)

    welcome = TelemetryStreamPacket(
        event=StreamEventType.CONNECTED,
        channel=channel,
        source_id="spacemedx-gateway",
        payload={"session_id": str(session_record.id), "user_id": str(user.id)},
    )
    await websocket.send_json(welcome.model_dump(mode="json"))

    try:
        while True:
            raw_data = await websocket.receive_json()

            if raw_data.get("event") == StreamEventType.HEARTBEAT.value:
                pong = TelemetryStreamPacket(
                    event=StreamEventType.HEARTBEAT,
                    channel=channel,
                    source_id="spacemedx-gateway",
                    payload={"status": "alive"},
                )
                await websocket.send_json(pong.model_dump(mode="json"))
                continue

            if user.role not in PUBLISH_ROLES:
                err = TelemetryStreamPacket(
                    event=StreamEventType.ERROR,
                    channel=channel,
                    source_id="spacemedx-gateway",
                    payload={"detail": "Role not permitted to publish telemetry."},
                )
                await websocket.send_json(err.model_dump(mode="json"))
                continue

            try:
                packet = TelemetryStreamPacket(
                    event=raw_data.get("event", StreamEventType.TELEMETRY_UPDATE),
                    channel=channel,
                    source_id=raw_data["source_id"],
                    payload=raw_data["payload"],
                )
            except (KeyError, ValidationError) as exc:
                err = TelemetryStreamPacket(
                    event=StreamEventType.ERROR,
                    channel=channel,
                    source_id="spacemedx-gateway",
                    payload={"detail": f"Invalid telemetry packet: {exc}"},
                )
                await websocket.send_json(err.model_dump(mode="json"))
                continue

            await telemetry_manager.broadcast(packet)

    except WebSocketDisconnect:
        pass
    finally:
        telemetry_manager.disconnect(websocket, channel)
        session_record.is_active = False
        session_record.disconnected_at = datetime.now(timezone.utc)
        await db.commit()


@router.get("/sessions", response_model=List[TelemetrySessionResponse])
async def list_stream_sessions(
    active_only: bool = False,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List WebSocket telemetry stream sessions for Mission Control diagnostics."""
    allowed_roles = {
        UserRole.SYSTEM_ADMIN,
        UserRole.ORG_ADMIN,
        UserRole.MISSION_ADMIN,
        UserRole.MISSION_CONTROL,
    }
    if current_user.role not in allowed_roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to view telemetry stream sessions.",
        )

    stmt = select(TelemetryStreamSession).order_by(TelemetryStreamSession.connected_at.desc())
    if active_only:
        stmt = stmt.where(TelemetryStreamSession.is_active.is_(True))

    result = await db.execute(stmt)
    return result.scalars().all()