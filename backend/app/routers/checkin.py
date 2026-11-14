from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.rbac import AuthenticatedUser, require_role
from app.db.session import get_db
from app.schemas.checkin import CheckInPayload, CheckInResponse
from app.services.attendance_service import AttendanceService

router = APIRouter(prefix="/attendance", tags=["Attendance Check-In"])


@router.post(
    "/check-in",
    response_model=CheckInResponse,
    status_code=status.HTTP_200_OK,
    summary="Submit Proximity Attendance Check-In",
)
async def check_in(
    payload: CheckInPayload,
    current_user: AuthenticatedUser = Depends(require_role(["student"])),
    db: AsyncSession = Depends(get_db),
):
    """
    Authoritative server-side attendance verification and recording engine:
    1. Validates active session window and expiration.
    2. Enforces verified student status and course enrollment.
    3. Validates ephemeral rotating BLE proximity challenge against HMAC window.
    4. Cryptographically verifies hardware-backed device signature when provided.
    5. Commits attendance record transactionally to PostgreSQL with idempotency guarantees.
    """
    return await AttendanceService.process_proximity_checkin(payload, current_user, db)


@router.post(
    "/proximity-checkin",
    response_model=CheckInResponse,
    status_code=status.HTTP_200_OK,
    include_in_schema=True,
    summary="Proximity Check-In Route (Legacy Compatibility)",
)
async def proximity_checkin(
    payload: CheckInPayload,
    current_user: AuthenticatedUser = Depends(require_role(["student"])),
    db: AsyncSession = Depends(get_db),
):
    """
    Backward-compatible alias for /check-in.
    """
    return await AttendanceService.process_proximity_checkin(payload, current_user, db)
