# app/api/v1/endpoints/ingestion.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from app.core.database import get_db
from app.models.user import User
from app.enums.user import UserRole
from app.core.security import get_current_user
from app.schemas.ingestion import IngestionCreate, IngestionResponse
from app.models.ingestion import IngestionLog
from app.enums.ingestion import IngestionStatus

router = APIRouter(prefix="/ingestion", tags=["Ingestion"])

@router.post("/batch", response_model=IngestionResponse, status_code=status.HTTP_201_CREATED)
async def ingest_batch_data(
    ingest_in: IngestionCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Ingest a batch of telemetry or sensor records (Restricted to system admin, mission admin, or mission control)."""
    if current_user.role not in [UserRole.SYSTEM_ADMIN, UserRole.MISSION_ADMIN, UserRole.MISSION_CONTROL]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have permission to ingest batch data."
        )

    # Ellenőrzés, hogy a batch_reference még nem létezik-e (duplikáció szűrés)
    existing_batch = await db.execute(
        select(IngestionLog).where(IngestionLog.batch_reference == ingest_in.batch_reference)
    )
    if existing_batch.scalars().first():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Batch reference '{ingest_in.batch_reference}' has already been ingested."
        )

    record_count = len(ingest_in.payload_data)

    db_log = IngestionLog(
        batch_reference=ingest_in.batch_reference,
        source_device_id=ingest_in.source_device_id,
        format=ingest_in.format,
        status=IngestionStatus.SUCCESS,
        records_processed=record_count
    )
    
    db.add(db_log)
    await db.commit()
    await db.refresh(db_log)
    
    return db_log

@router.get("/logs", response_model=List[IngestionResponse], status_code=status.HTTP_200_OK)
async def list_ingestion_logs(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Retrieve all ingestion audit logs."""
    result = await db.execute(select(IngestionLog))
    logs = result.scalars().all()
    return logs