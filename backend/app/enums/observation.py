# app/enums/observation.py
from enum import Enum

class ObservationQuality(str, Enum):
    VALID = "valid"
    QUESTIONABLE = "questionable"
    INVALID = "invalid"
    MISSING = "missing"

class ObservationSource(str, Enum):
    SIMULATOR = "simulator"
    WEARABLE = "wearable"
    MANUAL = "manual"
    MEDICAL_DEVICE = "medical_device"