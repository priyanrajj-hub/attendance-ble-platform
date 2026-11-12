from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel
from typing import Optional

router = APIRouter(prefix="/attendance", tags=["Attendance Check-In"])


class CheckInPayload(BaseModel):
    session_id: str
    ephemeral_nonce: str
    observed_rssi: int
    signature: Optional[str] = None


@router.post("/check-in", status_code=status.HTTP_501_NOT_IMPLEMENTED)
async def check_in_stub(payload: CheckInPayload):
    """
    Contract interface stub for BLE proximity check-in.
    Returns HTTP 501 Not Implemented until Phase 3/4 hardware calibration.
    """
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Proximity check-in is pending BLE field calibration in Phase 3/4. Interface stub active.",
    )
