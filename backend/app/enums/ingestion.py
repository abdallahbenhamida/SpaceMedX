# app/enums/ingestion.py
from enum import Enum

class IngestionFormat(str, Enum):
    JSON = "json"
    CSV = "csv"
    BINARY = "binary"

class IngestionStatus(str, Enum):
    SUCCESS = "success"
    PARTIAL = "partial"
    FAILED = "failed"