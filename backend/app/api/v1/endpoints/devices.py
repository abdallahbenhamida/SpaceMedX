# app/api/v1/endpoints/devices.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from app.core.database import get_db
from app.models.user import User
from app.enums.user import UserRole
from app.core.security import get_current_user
from app.schemas.device import DeviceCreate, DeviceResponse
from app.models.device import Device

router = APIRouter(prefix="/devices", tags=["Devices"])

@router.post("", response_model=DeviceResponse, status_code=status.HTTP_201_CREATED)
async def register_device(
    device_in: DeviceCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Register a new hardware or telemetry device (Restricted to system admin, mission admin, or mission control)."""
    if current_user.role not in [UserRole.SYSTEM_ADMIN, UserRole.MISSION_ADMIN, UserRole.MISSION_CONTROL]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have permission to register devices."
        )

    existing_device = await db.execute(
        select(Device).where(Device.serial_number == device_in.serial_number)
    )
    if existing_device.scalars().first():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Device with serial number '{device_in.serial_number}' already exists."
        )

    db_device = Device(
        serial_number=device_in.serial_number,
        name=device_in.name,
        device_type=device_in.device_type,
        status=device_in.status,
        firmware_version=device_in.firmware_version
    )
    
    db.add(db_device)
    await db.commit()
    await db.refresh(db_device)
    
    return db_device

@router.get("", response_model=List[DeviceResponse], status_code=status.HTTP_200_OK)
async def list_devices(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Retrieve all devices accessible to the authenticated user."""
    result = await db.execute(select(Device))
    devices = result.scalars().all()
    return devices