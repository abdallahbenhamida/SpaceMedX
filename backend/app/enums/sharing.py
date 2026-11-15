# app/enums/sharing.py
from enum import Enum

class SharedResourceType(str, Enum):
    MEDICAL_RECORD = "medical_record"
    TELEMETRY = "telemetry"
    ENVIRONMENTAL_LOG = "environmental_log"
    REPORT = "report"

class SharingPermission(str, Enum):
    READ = "read"
    EXPORT = "export"
    FULL = "full"