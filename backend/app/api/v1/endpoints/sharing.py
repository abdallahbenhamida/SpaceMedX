# app/api/v1/endpoints/sharing.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from app.core.database import get_db
from app.models.user import User
from app.enums.user import UserRole
from app.core.security import get_current_user
from app.schemas.sharing import ResourceShareCreate, ResourceShareResponse
from app.models.sharing import ResourceShare

router = APIRouter(prefix="/sharing", tags=["Sharing"])

@router.post("", response_model=ResourceShareResponse, status_code=status.HTTP_201_CREATED)
async def create_resource_share(
    share_in: ResourceShareCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Share a clinical or telemetry resource with another user (Restricted to system admin, org admin, mission admin, or medical officer)."""
    if current_user.role not in [UserRole.SYSTEM_ADMIN, UserRole.ORG_ADMIN, UserRole.MISSION_ADMIN, UserRole.MEDICAL_OFFICER]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have permission to share resources."
        )

    db_share = ResourceShare(
        resource_type=share_in.resource_type,
        resource_id=share_in.resource_id,
        owner_id=str(current_user.id),
        recipient_id=share_in.recipient_id,
        permission=share_in.permission
    )
    
    db.add(db_share)
    await db.commit()
    await db.refresh(db_share)
    
    return db_share

@router.get("", response_model=List[ResourceShareResponse], status_code=status.HTTP_200_OK)
async def list_resource_shares(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Retrieve all resource shares accessible or owned by the authenticated user."""
    result = await db.execute(select(ResourceShare))
    shares = result.scalars().all()
    return shares