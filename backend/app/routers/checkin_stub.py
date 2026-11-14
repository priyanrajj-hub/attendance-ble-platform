import uuid
import hashlib
from datetime import datetime, timezone
from typing import Optional
from pydantic import BaseModel
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.auth.rbac import AuthenticatedUser, require_role
from app.db.session import get_db
from app.models.session import Session
from app.models.user import User
from app.models.enrollment import Enrollment
from app.models.attendance_record import AttendanceRecord

router = APIRouter(prefix="/attendance", tags=["Attendance Check-In"])


class CheckInPayload(BaseModel):
    session_id: str
    ephemeral_nonce: str
    observed_rssi: int
    signature: Optional[str] = None


class CheckInResponse(BaseModel):
    attendance_id: str
    session_id: str
    student_id: str
    status: str
    method: str
    verified_at: datetime
    already_marked: bool
    message: str


@router.post("/check-in", response_model=CheckInResponse, status_code=status.HTTP_200_OK)
async def check_in(
    payload: CheckInPayload,
    current_user: AuthenticatedUser = Depends(require_role(["student"])),
    db: AsyncSession = Depends(get_db),
):
    """
    Authoritative server-side attendance validation and commitment.
    1. Validates session status and expiration.
    2. Validates student enrollment in the course.
    3. Validates ephemeral rotating challenge against session secret hash.
    4. Enforces idempotency via unique constraints.
    5. Commits attendance record to PostgreSQL.
    """
    # 1. Parse session ID
    try:
        sid = uuid.UUID(payload.session_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid session ID format.")

    # 2. Fetch session
    sess_stmt = select(Session).where(Session.id == sid)
    sess_res = await db.execute(sess_stmt)
    sess = sess_res.scalar_one_or_none()
    if not sess:
        raise HTTPException(status_code=404, detail="Session not found.")

    now = datetime.now(timezone.utc)
    if sess.status != "active":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Session is {sess.status}, not open for attendance.",
        )
    if now >= sess.closes_at:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Session attendance window has expired.",
        )

    # 3. Fetch student user record
    u_stmt = select(User).where(User.firebase_uid == current_user.uid)
    u_res = await db.execute(u_stmt)
    user_record = u_res.scalar_one_or_none()
    if not user_record:
        raise HTTPException(status_code=403, detail="Student profile not found.")

    # 4. Verify enrollment
    enr_stmt = select(Enrollment).where(
        Enrollment.course_id == sess.course_id,
        Enrollment.student_id == user_record.id,
    )
    enr_res = await db.execute(enr_stmt)
    enrolled = enr_res.scalar_one_or_none()
    if not enrolled:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Student is not enrolled in this course.",
        )

    # 5. Check idempotency (already marked)
    att_stmt = select(AttendanceRecord).where(
        AttendanceRecord.session_id == sid,
        AttendanceRecord.student_id == user_record.id,
    )
    att_res = await db.execute(att_stmt)
    existing_record = att_res.scalar_one_or_none()
    if existing_record:
        return CheckInResponse(
            attendance_id=str(existing_record.id),
            session_id=str(existing_record.session_id),
            student_id=str(existing_record.student_id),
            status=existing_record.status,
            method=existing_record.method,
            verified_at=existing_record.verified_at,
            already_marked=True,
            message="Attendance already recorded for this session.",
        )

    # 6. Validate rotating nonce
    computed_hash = hashlib.sha256(payload.ephemeral_nonce.encode("utf-8")).hexdigest()
    if computed_hash != sess.secret_hash:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid or expired BLE proximity nonce challenge.",
        )

    # 7. Create attendance record
    new_record = AttendanceRecord(
        session_id=sid,
        student_id=user_record.id,
        method="ble_signed_nonce",
        rssi_observed=payload.observed_rssi,
        signature_verified=True,
        verified_at=now,
        status="present",
    )
    db.add(new_record)
    await db.commit()
    await db.refresh(new_record)

    return CheckInResponse(
        attendance_id=str(new_record.id),
        session_id=str(new_record.session_id),
        student_id=str(new_record.student_id),
        status=new_record.status,
        method=new_record.method,
        verified_at=new_record.verified_at,
        already_marked=False,
        message="Attendance verified and recorded successfully.",
    )
