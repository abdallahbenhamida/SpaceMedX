from enum import Enum

class AuditAction(str, Enum):
    READ = "READ"
    CREATE = "CREATE"
    UPDATE = "UPDATE"
    DELETE = "DELETE"
    SHARE = "SHARE"
    EXPORT = "EXPORT"
    EMERGENCY_GRANT = "EMERGENCY_GRANT"
    EMERGENCY_REVOKE = "EMERGENCY_REVOKE"