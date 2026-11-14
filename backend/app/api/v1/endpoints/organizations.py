from uuid import UUID
from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User
from app.enums.user import UserRole
from app.models.organizations import Organization, OrganizationMembership
from app.schemas.organizations import (
    OrganizationCreate,
    OrganizationUpdate,
    OrganizationResponse,
    OrganizationMembershipCreate,
    OrganizationMembershipResponse,
)

router = APIRouter(prefix="/organizations", tags=["Organizations"])

@router.post("", response_model=OrganizationResponse, status_code=status.HTTP_201_CREATED)
async def create_organization(
    payload: OrganizationCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Create a new research organization (System Admin / Org Admin only)."""
    if current_user.role not in {UserRole.SYSTEM_ADMIN, UserRole.ORG_ADMIN}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to create organizations.")

    existing = await db.execute(select(Organization).where(Organization.code == payload.code))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Organization with this code already exists.")

    org = Organization(**payload.model_dump())
    db.add(org)
    await db.commit()
    await db.refresh(org)
    return org

@router.get("", response_model=List[OrganizationResponse])
async def list_organizations(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List all research organizations."""
    result = await db.execute(select(Organization).order_by(Organization.name))
    return result.scalars().all()

@router.get("/{org_id}", response_model=OrganizationResponse)
async def get_organization(
    org_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get organization details by ID."""
    org = await db.get(Organization, org_id)
    if not org:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Organization not found.")
    return org

@router.post("/{org_id}/members", response_model=OrganizationMembershipResponse, status_code=status.HTTP_201_CREATED)
async def add_organization_member(
    org_id: UUID,
    payload: OrganizationMembershipCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Assign a user to an organization with a scoped UserRole."""
    if current_user.role not in {UserRole.SYSTEM_ADMIN, UserRole.ORG_ADMIN}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to manage members.")

    org = await db.get(Organization, org_id)
    if not org:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Organization not found.")

    user = await db.get(User, payload.user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")

    membership = OrganizationMembership(
        user_id=payload.user_id,
        organization_id=org_id,
        role_in_org=payload.role_in_org,
    )
    db.add(membership)
    await db.commit()
    await db.refresh(membership)
    return membership