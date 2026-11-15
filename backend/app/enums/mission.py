# app/enums/mission.py
from enum import Enum

class MissionType(str, Enum):
    LUNAR = "lunar"
    MARS = "mars"
    ISS = "iss"
    DEEP_SPACE = "deep_space"
    ASTEROID = "asteroid"

class MissionStatus(str, Enum):
    PLANNED = "planned"
    ACTIVE = "active"
    COMPLETED = "completed"
    ABORTED = "aborted"