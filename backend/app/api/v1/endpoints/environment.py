# app/api/v1/endpoints/environment.py
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from app.core.database import get_db
from app.models.user import User, UserRole
from app.models.environment import EnvironmentalTelemetry
from app.schemas.environment import EnvironmentalTelemetryCreate, EnvironmentalTelemetryResponse
from app.enums.environment import MissionLocationType
from app.core.security import get_current_user

router = APIRouter(prefix="/environment", tags=["Habitat & Environment"])

@router.post("/telemetry", response_model=EnvironmentalTelemetryResponse, status_code=status.HTTP_201_CREATED)
async def ingest_environmental_telemetry(
    telemetry_in: EnvironmentalTelemetryCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Ingest habitat or environmental sensor readings (Restricted to authorized mission roles)."""
    # Use valid attributes from UserRole enum
    allowed_roles = [
        UserRole.MEDICAL_OFFICER, 
        UserRole.MISSION_CONTROL, 
        UserRole.MISSION_ADMIN, 
        UserRole.ORG_ADMIN, 
        UserRole.SYSTEM_ADMIN
    ]
    if current_user.role not in allowed_roles:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to ingest environmental telemetry."
        )

    telemetry_record = EnvironmentalTelemetry(**telemetry_in.model_dump())
    db.add(telemetry_record)
    await db.commit()
    await db.refresh(telemetry_record)
    return telemetry_record

@router.get("/telemetry", response_model=List[EnvironmentalTelemetryResponse])
async def get_environmental_telemetry(
    location_type: MissionLocationType | None = Query(None, description="Filter by location type (space, moon, planet, etc.)"),
    location_identifier: str | None = Query(None, description="Filter by specific hab/base identifier"),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Query historical and real-time environmental telemetry across space missions."""
    query = select(EnvironmentalTelemetry).order_by(EnvironmentalTelemetry.recorded_at.desc())

    if location_type:
        query = query.where(EnvironmentalTelemetry.location_type == location_type)
    if location_identifier:
        query = query.where(EnvironmentalTelemetry.location_identifier == location_identifier)

    query = query.limit(limit)
    result = await db.execute(query)
    records = result.scalars().all()
    return records