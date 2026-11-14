# app/api/v1/endpoints/subjects.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from app.core.database import get_db
from app.models.user import User
from app.enums.user import UserRole
from app.core.security import get_current_user
from app.schemas.subject import SubjectCreate, SubjectResponse
from app.models.subject import Subject

router = APIRouter(prefix="/subjects", tags=["Subjects"])

@router.post("", response_model=SubjectResponse, status_code=status.HTTP_201_CREATED)
async def create_subject(
    subject_in: SubjectCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Create a new research or clinical subject (Restricted to system admin, researcher, or medical officer)."""
    if current_user.role not in [UserRole.SYSTEM_ADMIN, UserRole.RESEARCHER, UserRole.MEDICAL_OFFICER]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have permission to create research subjects."
        )

    existing_subject = await db.execute(
        select(Subject).where(Subject.code == subject_in.code)
    )
    if existing_subject.scalars().first():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Subject with code '{subject_in.code}' already exists."
        )

    db_subject = Subject(
        code=subject_in.code,
        name=subject_in.name,
        category=subject_in.category,
        status=subject_in.status,
        description=subject_in.description
    )
    
    db.add(db_subject)
    await db.commit()
    await db.refresh(db_subject)
    
    return db_subject

@router.get("", response_model=List[SubjectResponse], status_code=status.HTTP_200_OK)
async def list_subjects(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Retrieve all subjects accessible to the authenticated user."""
    result = await db.execute(select(Subject))
    subjects = result.scalars().all()
    return subjects