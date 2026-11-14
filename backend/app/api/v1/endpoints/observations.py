# app/api/v1/endpoints/observations.py
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List
import uuid

from app.core.database import get_db
from app.models.user import User
from app.enums.user import UserRole
from app.core.security import get_current_user
from app.schemas.observation import ObservationCreate, ObservationResponse
from app.models.observation import Observation

router = APIRouter(prefix="/observations", tags=["Observations"])

@router.post("", response_model=ObservationResponse, status_code=status.HTTP_201_CREATED)
async def create_observation(
    obs_in: ObservationCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Record a new health observation or measurement (Restricted to medical officer, mission control, mission admin, or system admin)."""
    if current_user.role not in [UserRole.SYSTEM_ADMIN, UserRole.MISSION_ADMIN, UserRole.MISSION_CONTROL, UserRole.MEDICAL_OFFICER]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have permission to record observations."
        )

    db_obs = Observation(
        organization_id=uuid.UUID(obs_in.organization_id),
        mission_id=uuid.UUID(obs_in.mission_id),
        subject_id=uuid.UUID(obs_in.subject_id),
        device_id=uuid.UUID(obs_in.device_id) if obs_in.device_id else None,
        parameter_id=uuid.UUID(obs_in.parameter_id),
        timestamp_utc=obs_in.timestamp_utc,
        value_numeric=obs_in.value_numeric,
        value_text=obs_in.value_text,
        unit=obs_in.unit,
        quality_status=obs_in.quality_status,
        source_type=obs_in.source_type,
        sync_batch_id=uuid.UUID(obs_in.sync_batch_id) if obs_in.sync_batch_id else None,
        metadata_info=obs_in.metadata_info
    )
    db.add(db_obs)
    await db.commit()
    await db.refresh(db_obs)
    return db_obs

@router.get("", response_model=List[ObservationResponse], status_code=status.HTTP_200_OK)
async def list_observations(
    subject_id: uuid.UUID | None = Query(None),
    parameter_id: uuid.UUID | None = Query(None),
    limit: int = Query(50, ge=1, le=500),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Retrieve health observations with optional filters for subject and parameter."""
    stmt = select(Observation)
    if subject_id:
        stmt = stmt.where(Observation.subject_id == subject_id)
    if parameter_id:
        stmt = stmt.where(Observation.parameter_id == parameter_id)
    stmt = stmt.order_by(Observation.timestamp_utc.desc()).limit(limit)

    result = await db.execute(stmt)
    return result.scalars().all()