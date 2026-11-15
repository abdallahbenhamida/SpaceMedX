# app/enums/device.py
from enum import Enum

class DeviceType(str, Enum):
    WEARABLE = "wearable"
    ENVIRONMENTAL_SENSOR = "environmental_sensor"
    MEDICAL_DIAGNOSTIC = "medical_diagnostic"
    HABITAT_CONTROLLER = "habitat_controller"
    COMMUNICATION_RELAY = "communication_relay"

class DeviceStatus(str, Enum):
    ONLINE = "online"
    OFFLINE = "offline"
    MAINTENANCE = "maintenance"
    FAULTY = "faulty"
    DECOMMISSIONED = "decommissioned"