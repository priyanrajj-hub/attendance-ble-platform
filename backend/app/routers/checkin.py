from typing import Optional
import uuid
from fastapi import APIRouter, Depends, Query, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.auth.rbac import AuthenticatedUser, require_role
from app.db.session import get_db
from app.schemas.checkin import CheckInPayload, CheckInResponse
from app.services.attendance_service import AttendanceService
from app.services.attendance_calculation_service import AttendanceCalculationService
from app.models.user import User

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


@router.get("/summary", summary="Get Authoritative Attendance Calculation Summary")
async def get_attendance_summary(
    student_id: Optional[str] = Query(None, description="Target student UUID or roll number (Faculty/Admin only)"),
    min_attendance_pct: float = Query(75.0, description="Minimum institutional attendance percentage threshold"),
    condonation_min_pct: float = Query(65.0, description="Minimum condonation threshold percentage"),
    current_user: AuthenticatedUser = Depends(require_role(["student", "faculty", "admin"])),
    db: AsyncSession = Depends(get_db),
):
    """
    Authoritative Attendance Calculation Engine:
    - Calculates exact attendance percentage per course and overall from PostgreSQL sessions.
    - Accurately tracks conducted vs attended vs missed sessions.
    - Computes exact safe skips remaining and classes needed to achieve minimum threshold.
    - Honors configurable institutional policy thresholds (e.g. 75% min, 65% condonation).
    - Students are strictly isolated to their own records.
    """
    if current_user.role == "student":
        u_stmt = select(User).where(User.firebase_uid == current_user.uid)
        u_res = await db.execute(u_stmt)
        user_record = u_res.scalar_one_or_none()
        if not user_record:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Student profile not found",
            )
        target_student_id = user_record.id
    else:
        if not student_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="student_id query parameter is required for faculty/admin requests",
            )
        try:
            target_student_id = uuid.UUID(student_id)
        except ValueError:
            # Try finding user by roll number or email
            u_stmt = select(User).where(
                (User.roll_number == student_id.strip()) | (User.email == student_id.strip())
            )
            u_res = await db.execute(u_stmt)
            target_user = u_res.scalar_one_or_none()
            if not target_user:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"Target student '{student_id}' not found",
                )
            target_student_id = target_user.id

    return await AttendanceCalculationService.get_attendance_summary(
        db=db,
        student_id=target_student_id,
        min_attendance_pct=min_attendance_pct,
        condonation_min_pct=condonation_min_pct,
    )
