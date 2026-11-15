# app/core/ws_manager.py
from collections import defaultdict
from fastapi import WebSocket
from app.enums.telemetry import TelemetryChannel
from app.schemas.telemetry import TelemetryStreamPacket


class TelemetryConnectionManager:
    def __init__(self) -> None:
        self.active_connections: dict[TelemetryChannel, set[WebSocket]] = defaultdict(set)

    async def connect(self, websocket: WebSocket, channel: TelemetryChannel) -> None:
        await websocket.accept()
        self.active_connections[channel].add(websocket)

    def disconnect(self, websocket: WebSocket, channel: TelemetryChannel) -> None:
        self.active_connections[channel].discard(websocket)

    async def broadcast(self, packet: TelemetryStreamPacket) -> None:
        targets = set(self.active_connections[packet.channel])
        if packet.channel != TelemetryChannel.ALL:
            targets |= self.active_connections[TelemetryChannel.ALL]

        message = packet.model_dump(mode="json")
        stale_connections: list[tuple[TelemetryChannel, WebSocket]] = []

        for ws in targets:
            try:
                await ws.send_json(message)
            except Exception:
                for ch, conns in self.active_connections.items():
                    if ws in conns:
                        stale_connections.append((ch, ws))

        for ch, ws in stale_connections:
            self.disconnect(ws, ch)


telemetry_manager = TelemetryConnectionManager()