# app/enums/telemetry.py
from enum import Enum


class TelemetryChannel(str, Enum):
    MEDICAL = "medical"
    ENVIRONMENT = "environment"
    EMERGENCY = "emergency"
    ALL = "all"


class StreamEventType(str, Enum):
    CONNECTED = "connected"
    TELEMETRY_UPDATE = "telemetry_update"
    ALERT = "alert"
    HEARTBEAT = "heartbeat"
    ERROR = "error"