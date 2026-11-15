# app/api/v1/endpoints/teams.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from app.core.database import get_db
from app.models.user import User
from app.enums.user import UserRole
from app.core.security import get_current_user
from app.schemas.team import (
    TeamCreate, TeamResponse,
    TeamMembershipCreate, TeamMembershipResponse,
    TeamLeadershipCreate, TeamLeadershipResponse
)
from app.models.team import Team, TeamMembership, TeamLeadership

router = APIRouter(prefix="/teams", tags=["Teams"])

@router.post("", response_model=TeamResponse, status_code=status.HTTP_201_CREATED)
async def create_team(
    team_in: TeamCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Create a new mission crew or team (Restricted to system admin, org admin, or mission admin)."""
    if current_user.role not in [UserRole.SYSTEM_ADMIN, UserRole.ORG_ADMIN, UserRole.MISSION_ADMIN]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have permission to create teams."
        )

    db_team = Team(
        organization_id=team_in.organization_id,
        mission_id=team_in.mission_id,
        team_name=team_in.team_name,
        team_type=team_in.team_type,
        status=team_in.status
    )
    db.add(db_team)
    await db.commit()
    await db.refresh(db_team)
    return db_team

@router.get("", response_model=List[TeamResponse], status_code=status.HTTP_200_OK)
async def list_teams(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Retrieve all teams accessible to the authenticated user."""
    result = await db.execute(select(Team))
    return result.scalars().all()

@router.post("/memberships", response_model=TeamMembershipResponse, status_code=status.HTTP_201_CREATED)
async def add_team_membership(
    membership_in: TeamMembershipCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Assign a subject to a team (Restricted to admin roles)."""
    if current_user.role not in [UserRole.SYSTEM_ADMIN, UserRole.ORG_ADMIN, UserRole.MISSION_ADMIN]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have permission to manage team memberships."
        )

    db_membership = TeamMembership(
        team_id=membership_in.team_id,
        subject_id=membership_in.subject_id,
        valid_until=membership_in.valid_until
    )
    db.add(db_membership)
    await db.commit()
    await db.refresh(db_membership)
    return db_membership

@router.post("/leaderships", response_model=TeamLeadershipResponse, status_code=status.HTTP_201_CREATED)
async def assign_team_leadership(
    leadership_in: TeamLeadershipCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Assign a team leader (Restricted to admin roles)."""
    if current_user.role not in [UserRole.SYSTEM_ADMIN, UserRole.ORG_ADMIN, UserRole.MISSION_ADMIN]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have permission to assign team leadership."
        )

    db_leadership = TeamLeadership(
        team_id=leadership_in.team_id,
        user_id=leadership_in.user_id,
        valid_until=leadership_in.valid_until
    )
    db.add(db_leadership)
    await db.commit()
    await db.refresh(db_leadership)
    return db_leadership