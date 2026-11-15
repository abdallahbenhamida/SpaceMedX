# app/api/v1/endpoints/medical.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import uuid

from app.core.database import get_db
from app.models.user import User, UserRole
from app.models.medical import MedicalRecord
from app.schemas.medical import MedicalRecordCreate, MedicalRecordResponse
from app.core.security import get_current_user

router = APIRouter(prefix="/medical", tags=["Medical Telemetry"])

@router.post("/records", response_model=MedicalRecordResponse, status_code=status.HTTP_201_CREATED)
async def create_medical_record(
    record_in: MedicalRecordCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Log a new medical record/telemetry entry. Restricted to medical officers."""
    if current_user.role != UserRole.MEDICAL_OFFICER:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only medical officers can log medical records."
        )

    # Verify target user exists
    target_user = await db.get(User, record_in.user_id)
    if not target_user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Crew member not found.")

    new_record = MedicalRecord(**record_in.model_dump())
    db.add(new_record)
    await db.commit()
    await db.refresh(new_record)
    return new_record

@router.get("/records/{user_id}", response_model=list[MedicalRecordResponse])
async def get_user_medical_records(
    user_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Retrieve medical history for a specific crew member."""
    # Users can view their own records, medical officers can view anyone's
    if current_user.id != user_id and current_user.role != UserRole.MEDICAL_OFFICER:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to access this crew member's medical history."
        )

    result = await db.execute(
        select(MedicalRecord)
        .where(MedicalRecord.user_id == user_id)
        .order_by(MedicalRecord.recorded_at.desc())
    )
    records = result.scalars().all()
    return records