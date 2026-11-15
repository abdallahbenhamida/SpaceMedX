# app/enums/organizations.py
from enum import Enum

class OrganizationStatus(str, Enum):
    ACTIVE = "active"
    SUSPENDED = "suspended"
    PENDING = "pending"