import uuid
import secrets
import hashlib
from datetime import datetime, timezone, timedelta
from typing import List, Optional
from pydantic import BaseModel
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.auth.rbac import AuthenticatedUser, get_current_user, require_role
from app.db.session import get_db
from app.models.session import Session
from app.models.course import Course
from app.models.user import User
from app.models.enrollment import Enrollment

router = APIRouter(prefix="/sessions", tags=["Attendance Sessions"])


class SessionStartRequest(BaseModel):
    course_id: str
    room_label: str
    duration_minutes: int = 50
    rssi_threshold: int = -75


class SessionResponse(BaseModel):
    id: str
    course_id: str
    room_label: str
    rssi_threshold: int
    opens_at: datetime
    closes_at: datetime
    status: str
    ephemeral_token: Optional[str] = None


@router.post("/start", response_model=SessionResponse, status_code=status.HTTP_201_CREATED)
async def start_session(
    payload: SessionStartRequest,
    current_user: AuthenticatedUser = Depends(require_role(["faculty", "admin"])),
    db: AsyncSession = Depends(get_db),
):
    """
    Starts an active BLE attendance session for a course.
    Generates a secure ephemeral rotating secret token.
    """
    try:
        cid = uuid.UUID(payload.course_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid course ID format.")

    # Check course exists
    c_stmt = select(Course).where(Course.id == cid)
    c_res = await db.execute(c_stmt)
    course = c_res.scalar_one_or_none()
    if not course:
        raise HTTPException(status_code=404, detail="Course not found.")

    # Get faculty user record
    u_stmt = select(User).where(User.firebase_uid == current_user.uid)
    u_res = await db.execute(u_stmt)
    user_record = u_res.scalar_one_or_none()
    if not user_record:
        raise HTTPException(status_code=403, detail="Faculty profile not found.")

    # Verify faculty owns course if not admin
    if current_user.role != "admin" and course.faculty_id != user_record.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not authorized to start sessions for this course.",
        )

    # Generate ephemeral nonce token
    ephemeral_token = secrets.token_hex(16)
    secret_hash = hashlib.sha256(ephemeral_token.encode("utf-8")).hexdigest()

    now = datetime.now(timezone.utc)
    closes_at = now + timedelta(minutes=payload.duration_minutes)

    new_session = Session(
        course_id=cid,
        started_by=user_record.id,
        room_label=payload.room_label.strip(),
        rssi_threshold=payload.rssi_threshold,
        secret_hash=secret_hash,
        opens_at=now,
        closes_at=closes_at,
        status="active",
    )
    db.add(new_session)
    await db.commit()
    await db.refresh(new_session)

    return SessionResponse(
        id=str(new_session.id),
        course_id=str(new_session.course_id),
        room_label=new_session.room_label,
        rssi_threshold=new_session.rssi_threshold,
        opens_at=new_session.opens_at,
        closes_at=new_session.closes_at,
        status=new_session.status,
        ephemeral_token=ephemeral_token,  # Returned only to starting faculty
    )


@router.post("/{session_id}/stop", response_model=SessionResponse)
async def stop_session(
    session_id: str,
    current_user: AuthenticatedUser = Depends(require_role(["faculty", "admin"])),
    db: AsyncSession = Depends(get_db),
):
    """
    Stops an active attendance session.
    """
    try:
        sid = uuid.UUID(session_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid session ID format.")

    stmt = select(Session).where(Session.id == sid)
    res = await db.execute(stmt)
    sess = res.scalar_one_or_none()
    if not sess:
        raise HTTPException(status_code=404, detail="Session not found.")

    sess.status = "closed"
    sess.closes_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(sess)

    return SessionResponse(
        id=str(sess.id),
        course_id=str(sess.course_id),
        room_label=sess.room_label,
        rssi_threshold=sess.rssi_threshold,
        opens_at=sess.opens_at,
        closes_at=sess.closes_at,
        status=sess.status,
    )


@router.get("/active", response_model=List[SessionResponse])
async def list_active_sessions(
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Lists active sessions for the authenticated student or faculty member.
    """
    now = datetime.now(timezone.utc)
    u_stmt = select(User).where(User.firebase_uid == current_user.uid)
    u_res = await db.execute(u_stmt)
    user_record = u_res.scalar_one_or_none()

    if not user_record:
        return []

    if current_user.role == "admin":
        stmt = select(Session).where(Session.status == "active", Session.closes_at > now)
    elif current_user.role == "faculty":
        stmt = (
            select(Session)
            .join(Course, Course.id == Session.course_id)
            .where(
                Course.faculty_id == user_record.id,
                Session.status == "active",
                Session.closes_at > now,
            )
        )
    else:
        # Student: only active sessions for courses they are enrolled in
        stmt = (
            select(Session)
            .join(Course, Course.id == Session.course_id)
            .join(Enrollment, Enrollment.course_id == Course.id)
            .where(
                Enrollment.student_id == user_record.id,
                Enrollment.status == "active",
                Session.status == "active",
                Session.closes_at > now,
            )
        )

    res = await db.execute(stmt)
    sessions = res.scalars().all()

    return [
        SessionResponse(
            id=str(s.id),
            course_id=str(s.course_id),
            room_label=s.room_label,
            rssi_threshold=s.rssi_threshold,
            opens_at=s.opens_at,
            closes_at=s.closes_at,
            status=s.status,
        )
        for s in sessions
    ]
