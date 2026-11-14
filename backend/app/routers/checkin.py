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


@router.get("/my-history", summary="Get Authenticated Student Attendance History")
async def get_my_history(
    current_user: AuthenticatedUser = Depends(require_role(["student"])),
    db: AsyncSession = Depends(get_db),
):
    """
    Authoritative attendance history directly from PostgreSQL.
    """
    from sqlalchemy import select
    from app.models.user import User
    from app.models.attendance_record import AttendanceRecord
    from app.models.session import Session
    from app.models.course import Course

    u_stmt = select(User).where(User.firebase_uid == current_user.uid)
    u_res = await db.execute(u_stmt)
    user_record = u_res.scalar_one_or_none()
    if not user_record:
        return []

    stmt = (
        select(AttendanceRecord, Session, Course)
        .join(Session, Session.id == AttendanceRecord.session_id)
        .join(Course, Course.id == Session.course_id)
        .where(AttendanceRecord.student_id == user_record.id)
        .order_by(AttendanceRecord.verified_at.desc())
    )
    res = await db.execute(stmt)
    records = []
    for att, sess, crs in res.all():
        records.append({
            "id": str(att.id),
            "session_id": str(att.session_id),
            "course_id": str(crs.id),
            "course_code": crs.code,
            "course_name": crs.name,
            "room_label": sess.room_label,
            "verified_at": att.verified_at,
            "status": att.status,
            "method": att.method,
            "rssi_observed": att.rssi_observed,
            "signature_verified": att.signature_verified,
        })
    return records
