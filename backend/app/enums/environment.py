# app/enums/environment.py
from enum import Enum

class MissionLocationType(str, Enum):
    SPACE = "space"             # Deep space transit / Orbital vessel
    MOON = "moon"               # Lunar surface base / Outpost
    PLANET = "planet"           # Planetary surface (e.g., Mars, Titan)
    HABITAT = "habitat"         # Orbital space station / ISS
    ASTEROID = "asteroid"       # Asteroid mining facility

class EnvironmentalMetricType(str, Enum):
    ATMOSPHERIC_PRESSURE = "atmospheric_pressure"  # e.g., kPa or mmHg
    CO2_LEVEL = "co2_level"                        # ppm
    O2_LEVEL = "o2_level"                          # percentage %
    RADIATION_EXPOSURE = "radiation_exposure"      # mSv/h or uSv/h
    AMBIENT_TEMPERATURE = "ambient_temperature"    # Celsius
    HUMIDITY = "humidity"                          # percentage %
    CABIN_AIRFLOW = "cabin_airflow"                # m/s

class EnvironmentAlertLevel(str, Enum):
    NOMINAL = "nominal"
    WARNING = "warning"
    CRITICAL = "critical"
    EMERGENCY = "emergency"