from enum import Enum

class UserRole(str, Enum):
    SYSTEM_ADMIN = "sys_admin"
    ORG_ADMIN = "org_admin"
    MISSION_ADMIN = "mission_admin"
    TEAM_LEADER = "team_leader"
    ASTRONAUT = "astronaut"
    MEDICAL_OFFICER = "medical_officer"
    RESEARCHER = "researcher"
    MISSION_CONTROL = "mission_control"
    GUEST_VIEWER = "guest_viewer"

class AccountStatus(str, Enum):
    ACTIVE = "active"
    OFFLINE = "offline"
    INVITED = "invited"
    SUSPENDED = "suspended"
    DEACTIVATED = "deactivated"