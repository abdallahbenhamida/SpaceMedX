# app/api/v1/endpoints/emergency.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime, timedelta, timezone
import uuid
from typing import List

from app.core.database import get_db
from app.models.user import User, UserRole
from app.models.emergency import EmergencyAccessGrant
from app.models.audit import AuditLog
from app.schemas.emergency import EmergencyGrantCreate, EmergencyGrantResponse
from app.enums.emergency import EmergencyGrantStatus
from app.enums.audit import AuditAction
from app.core.security import get_current_user

router = APIRouter(prefix="/emergency", tags=["Emergency Protocols"])

@router.post("/grants", response_model=EmergencyGrantResponse, status_code=status.HTTP_201_CREATED)
async def create_emergency_grant(
    grant_in: EmergencyGrantCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Issue a temporary emergency access override grant. Restricted to Medical Officers or Mission Admins."""
    allowed_roles = [UserRole.MEDICAL_OFFICER, UserRole.MISSION_ADMIN, UserRole.SYSTEM_ADMIN, UserRole.ORG_ADMIN]
    if current_user.role not in allowed_roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to issue emergency override grants."
        )

    grantee = await db.get(User, grant_in.grantee_id)
    if not grantee:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Grantee user not found.")

    expires_at = datetime.now(timezone.utc) + timedelta(hours=grant_in.duration_hours)

    grant_record = EmergencyAccessGrant(
        grantor_id=current_user.id,
        grantee_id=grant_in.grantee_id,
        reason=grant_in.reason,
        status=EmergencyGrantStatus.ACTIVE,
        expires_at=expires_at
    )
    db.add(grant_record)

    # Log audit trail using your uppercase AuditAction enum
    audit_log = AuditLog(
        user_id=current_user.id,
        action=AuditAction.EMERGENCY_GRANT,
        resource="emergency_access_grants",
        details=f"Issued emergency grant to user {grant_in.grantee_id} for reason: {grant_in.reason}"
    )
    db.add(audit_log)

    await db.commit()
    await db.refresh(grant_record)
    return grant_record

@router.get("/grants", response_model=List[EmergencyGrantResponse])
async def list_emergency_grants(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """List active emergency access grants. Restricted to administrative/medical/control roles."""
    allowed_roles = [UserRole.MEDICAL_OFFICER, UserRole.MISSION_ADMIN, UserRole.SYSTEM_ADMIN, UserRole.ORG_ADMIN, UserRole.MISSION_CONTROL]
    if current_user.role not in allowed_roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to view emergency grants."
        )

    result = await db.execute(select(EmergencyAccessGrant).order_by(EmergencyAccessGrant.created_at.desc()))
    return result.scalars().all()

@router.patch("/grants/{grant_id}/revoke", response_model=EmergencyGrantResponse)
async def revoke_emergency_grant(
    grant_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Revoke an active emergency access grant early."""
    allowed_roles = [UserRole.MEDICAL_OFFICER, UserRole.MISSION_ADMIN, UserRole.SYSTEM_ADMIN, UserRole.ORG_ADMIN]
    if current_user.role not in allowed_roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to revoke emergency grants."
        )

    grant = await db.get(EmergencyAccessGrant, grant_id)
    if not grant:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Emergency grant not found.")

    grant.status = EmergencyGrantStatus.REVOKED

    # Log audit trail using your uppercase AuditAction enum
    audit_log = AuditLog(
        user_id=current_user.id,
        action=AuditAction.EMERGENCY_REVOKE,
        resource="emergency_access_grants",
        details=f"Revoked emergency grant {grant_id}"
    )
    db.add(audit_log)

    await db.commit()
    await db.refresh(grant)
    return grant