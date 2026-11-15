# app/api/v1/endpoints/mobile_sync.py
from fastapi import APIRouter, Depends, Request, Response, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import json
import hashlib

from app.core.database import get_db
from app.models.mobile_sync import MobileMeasurementRecord

router = APIRouter(prefix="/measurement/save", tags=["Mobile HUB Sync"])

@router.get("")
@router.get("/")
async def connection_test():
    """Connection test endpoint for mobile HUB (GET {base})."""
    return {"status": "connected", "service": "SpaceMedX HUB v1.3 Server"}

@router.post("/{user_id}/{measurement_type}/{count}/{from_ts}/{to_ts}")
async def save_measurements(
    user_id: str,
    measurement_type: str,
    count: int,
    from_ts: str,
    to_ts: str,
    request: Request,
    profil: int = 0,
    deviceid: int = 0,
    ext: int = 1,
    db: AsyncSession = Depends(get_db)
):
    """
    Receives measurement batches from the mobile HUB.
    Parses raw body as JSON array and ignores duplicates.
    """
    body_bytes = await request.body()
    try:
        records = json.loads(body_bytes.decode("utf-8"))
    except Exception:
        records = []

    if not isinstance(records, list):
        records = [records] if records else []

    for record in records:
        # Generate deterministic content hash for idempotency (userId + type + record content)
        record_str = json.dumps(record, sort_keys=True)
        raw_hash_key = f"{user_id}:{measurement_type}:{record_str}"
        content_hash = hashlib.sha256(raw_hash_key.encode("utf-8")).hexdigest()

        # Check if duplicate exists
        existing = await db.execute(
            select(MobileMeasurementRecord).where(MobileMeasurementRecord.content_hash == content_hash)
        )
        if existing.scalar_one_or_none():
            continue  # Ignore duplicate silently as required by spec

        db_record = MobileMeasurementRecord(
            user_id=user_id,
            measurement_type=measurement_type,
            count=count,
            from_timestamp=from_ts,
            to_timestamp=to_ts,
            record_data=record,
            content_hash=content_hash
        )
        db.add(db_record)

    await db.commit()
    # Response body is ignored by client; any 2xx accepts the batch
    return Response(status_code=status.HTTP_200_OK)