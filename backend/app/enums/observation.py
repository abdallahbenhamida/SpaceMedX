from enum import Enum

class ObservationQuality(str, Enum):
    VALID = "Valid"
    QUESTIONABLE = "Questionable"
    INVALID = "Invalid"
    MISSING = "Missing"

class ObservationSource(str, Enum):
    SIMULATOR = "Simulator"
    WEARABLE = "Wearable"
    MANUAL = "Manual"
    MEDICAL_DEVICE = "Medical Device"