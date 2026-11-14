# app/enums/team.py
from enum import Enum

class TeamType(str, Enum):
    SQUAD = "squad"
    CREW = "crew"
    GROUP = "group"
    DEPARTMENT = "department"

class TeamStatus(str, Enum):
    ACTIVE = "active"
    STANDBY = "standby"
    DISBANDED = "disbanded"