# app/enums/subject.py
from enum import Enum

class SubjectCategory(str, Enum):
    HUMAN = "human"
    BIOLOGICAL_SAMPLE = "biological_sample"
    MATERIALS_SCIENCE = "materials_science"
    HARDWARE_COMPONENT = "hardware_component"

class SubjectStatus(str, Enum):
    ACTIVE = "active"
    MONITORING_COMPLETE = "monitoring_complete"
    QUARANTINED = "quarantined"
    ARCHIVED = "archived"