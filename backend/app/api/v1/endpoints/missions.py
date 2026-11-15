# app/api/v1/endpoints/missions.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from app.core.database import get_db
from app.models.user import User
from app.enums.user import UserRole
from app.core.security import get_current_user
from app.schemas.mission import MissionCreate, MissionResponse
from app.models.mission import Mission

router = APIRouter(prefix="/missions", tags=["Missions"])

@router.post("", response_model=MissionResponse, status_code=status.HTTP_201_CREATED)
async def create_mission(
    mission_in: MissionCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Create a new space mission (Restricted to system or mission admin roles)."""
    # 1. Enforce RBAC permissions using correct SYSTEM_ADMIN attribute
    if current_user.role not in [UserRole.SYSTEM_ADMIN, UserRole.MISSION_ADMIN]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have permission to create missions."
        )

    # 2. Check if a mission with the same code already exists
    existing_mission = await db.execute(
        select(Mission).where(Mission.code == mission_in.code)
    )
    if existing_mission.scalars().first():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Mission with code '{mission_in.code}' already exists."
        )

    # 3. Instantiate and save the new mission
    db_mission = Mission(
        name=mission_in.name,
        code=mission_in.code,
        mission_type=mission_in.mission_type,
        status=mission_in.status,
        is_active=mission_in.is_active
    )
    
    db.add(db_mission)
    await db.commit()
    await db.refresh(db_mission)
    
    return db_mission

@router.get("", response_model=List[MissionResponse], status_code=status.HTTP_200_OK)
async def list_missions(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Retrieve all missions accessible to the authenticated user."""
    result = await db.execute(select(Mission))
    missions = result.scalars().all()
    return missions