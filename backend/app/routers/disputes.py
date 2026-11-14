import uuid
import hashlib
from datetime import datetime, timezone
from typing import List, Optional
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.auth.rbac import AuthenticatedUser, get_current_user, require_role
from app.db.session import get_db
from app.models.dispute import Dispute
from app.models.session import Session
from app.models.course import Course
from app.models.user import User
from app.models.enrollment import Enrollment
from app.models.attendance_record import AttendanceRecord
from app.models.override import Override
from app.models.audit_log import AuditLog

router = APIRouter(prefix="/disputes", tags=["Attendance Disputes & Corrections"])


class DisputeCreateRequest(BaseModel):
    session_id: str
    reason: str = Field(..., min_length=5, max_length=1000)


class DisputeResolveRequest(BaseModel):
    decision: str = Field(..., pattern="^(approved|rejected)$")
    resolution_notes: Optional[str] = Field(None, max_length=1000)


class DisputeResponse(BaseModel):
    id: str
    session_id: str
    course_id: str
    course_code: str
    course_name: str
    student_id: str
    student_name: str
    roll_number: Optional[str] = None
    reason: str
    status: str
    resolved_by: Optional[str] = None
    resolution_notes: Optional[str] = None
    created_at: datetime
    resolved_at: Optional[datetime] = None


@router.post("", response_model=DisputeResponse, status_code=status.HTTP_201_CREATED)
async def submit_dispute(
    payload: DisputeCreateRequest,
    current_user: AuthenticatedUser = Depends(require_role(["student"])),
    db: AsyncSession = Depends(get_db),
):
    """
    Submits an attendance correction request / dispute for a session.
    Enforces student course enrollment and session existence.
    """
    try:
        sid = uuid.UUID(payload.session_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid session ID format.")

    # 1. Resolve student record
    u_stmt = select(User).where(User.firebase_uid == current_user.uid)
    u_res = await db.execute(u_stmt)
    student = u_res.scalar_one_or_none()
    if not student:
        raise HTTPException(status_code=403, detail="Student user record not found.")

    # 2. Check session and course
    s_stmt = select(Session, Course).join(Course, Course.id == Session.course_id).where(Session.id == sid)
    s_res = await db.execute(s_stmt)
    sess_row = s_res.first()
    if not sess_row:
        raise HTTPException(status_code=404, detail="Attendance session not found.")
    sess, course = sess_row

    # 3. Verify student is enrolled in the course
    enr_stmt = select(Enrollment).where(
        Enrollment.course_id == course.id,
        Enrollment.student_id == student.id,
        Enrollment.status == "active",
    )
    enr_res = await db.execute(enr_stmt)
    if not enr_res.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not enrolled in the course associated with this session.",
        )

    # 4. Check for existing pending dispute
    disp_check = select(Dispute).where(
        Dispute.session_id == sid,
        Dispute.student_id == student.id,
        Dispute.status == "pending",
    )
    disp_res = await db.execute(disp_check)
    if disp_res.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A pending attendance dispute for this session already exists.",
        )

    # 5. Create dispute
    now = datetime.now(timezone.utc)
    new_dispute = Dispute(
        session_id=sid,
        student_id=student.id,
        reason=payload.reason.strip(),
        status="pending",
        created_at=now,
    )
    db.add(new_dispute)
    await db.flush()

    # 6. Audit log entry
    audit_entry = AuditLog(
        actor_id=student.id,
        action="submit_dispute",
        target_entity="disputes",
        target_id=str(new_dispute.id),
        ip_hash=hashlib.sha256(student.firebase_uid.encode("utf-8")).hexdigest()[:64],
        request_id=uuid.uuid4().hex,
        payload={
            "session_id": str(sid),
            "reason": payload.reason.strip(),
        },
        created_at=now,
    )
    db.add(audit_entry)
    await db.commit()
    await db.refresh(new_dispute)

    return DisputeResponse(
        id=str(new_dispute.id),
        session_id=str(sess.id),
        course_id=str(course.id),
        course_code=course.code,
        course_name=course.name,
        student_id=str(student.id),
        student_name=student.display_name,
        roll_number=student.roll_number,
        reason=new_dispute.reason,
        status=new_dispute.status,
        resolved_by=None,
        resolution_notes=None,
        created_at=new_dispute.created_at,
        resolved_at=None,
    )


@router.get("", response_model=List[DisputeResponse])
async def list_disputes(
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Lists disputes scoped by user role:
    - Student: sees own submitted disputes.
    - Faculty: sees disputes for sessions in courses taught by faculty.
    - Admin: sees all disputes.
    """
    u_stmt = select(User).where(User.firebase_uid == current_user.uid)
    u_res = await db.execute(u_stmt)
    user_record = u_res.scalar_one_or_none()
    if not user_record:
        return []

    stmt = (
        select(Dispute, Session, Course, User)
        .join(Session, Session.id == Dispute.session_id)
        .join(Course, Course.id == Session.course_id)
        .join(User, User.id == Dispute.student_id)
    )

    if current_user.role == "student":
        stmt = stmt.where(Dispute.student_id == user_record.id)
    elif current_user.role == "faculty":
        stmt = stmt.where(Course.faculty_id == user_record.id)
    # Admin sees all

    stmt = stmt.order_by(Dispute.created_at.desc())
    res = await db.execute(stmt)
    disputes = res.all()

    response = []
    for disp, sess, course, student in disputes:
        response.append(
            DisputeResponse(
                id=str(disp.id),
                session_id=str(sess.id),
                course_id=str(course.id),
                course_code=course.code,
                course_name=course.name,
                student_id=str(student.id),
                student_name=student.display_name,
                roll_number=student.roll_number,
                reason=disp.reason,
                status=disp.status,
                resolved_by=str(disp.resolved_by) if disp.resolved_by else None,
                resolution_notes=disp.resolution_notes,
                created_at=disp.created_at,
                resolved_at=disp.resolved_at,
            )
        )
    return response


@router.post("/{dispute_id}/resolve", response_model=DisputeResponse)
async def resolve_dispute(
    dispute_id: str,
    payload: DisputeResolveRequest,
    current_user: AuthenticatedUser = Depends(require_role(["faculty", "admin"])),
    db: AsyncSession = Depends(get_db),
):
    """
    Resolves an attendance dispute (Approve or Reject).
    Faculty must own the course.
    If approved:
    1. Idempotently updates or inserts AttendanceRecord as present_override.
    2. Inserts an Override audit row in PostgreSQL.
    3. Writes immutable AuditLog row.
    4. Marks dispute approved.
    """
    try:
        did = uuid.UUID(dispute_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid dispute ID format.")

    stmt = (
        select(Dispute, Session, Course, User)
        .join(Session, Session.id == Dispute.session_id)
        .join(Course, Course.id == Session.course_id)
        .join(User, User.id == Dispute.student_id)
        .where(Dispute.id == did)
    )
    res = await db.execute(stmt)
    row = res.first()
    if not row:
        raise HTTPException(status_code=404, detail="Dispute not found.")
    dispute, sess, course, student = row

    # Enforce faculty course ownership if not admin
    u_stmt = select(User).where(User.firebase_uid == current_user.uid)
    u_res = await db.execute(u_stmt)
    resolver_record = u_res.scalar_one_or_none()
    if not resolver_record:
        raise HTTPException(status_code=403, detail="Resolver user record not found.")

    if current_user.role != "admin" and course.faculty_id != resolver_record.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not authorized to resolve disputes for another instructor's course.",
        )

    if dispute.status != "pending":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Dispute is already resolved ({dispute.status}).",
        )

    now = datetime.now(timezone.utc)
    dispute.status = payload.decision
    dispute.resolved_by = resolver_record.id
    dispute.resolution_notes = payload.resolution_notes
    dispute.resolved_at = now

    if payload.decision == "approved":
        # Check existing attendance record
        att_stmt = select(AttendanceRecord).where(
            AttendanceRecord.session_id == sess.id,
            AttendanceRecord.student_id == student.id,
        )
        att_res = await db.execute(att_stmt)
        record = att_res.scalar_one_or_none()

        override_reason = f"Dispute #{str(dispute.id)[:8]} approved: {payload.resolution_notes or dispute.reason}"

        if record:
            record.status = "present"
            record.method = "faculty_manual_override"
            record.override_reason = override_reason
            record.marked_by = resolver_record.id
            record.verified_at = now
        else:
            record = AttendanceRecord(
                session_id=sess.id,
                student_id=student.id,
                method="faculty_manual_override",
                status="present",
                verified_at=now,
                signature_verified=False,
                override_reason=override_reason,
                marked_by=resolver_record.id,
            )
            db.add(record)
            await db.flush()

        # Insert Override row
        override_entry = Override(
            record_id=record.id,
            session_id=sess.id,
            student_id=student.id,
            actor_id=resolver_record.id,
            action="grant",
            reason=override_reason,
            created_at=now,
        )
        db.add(override_entry)

    # Immutable audit log
    audit_entry = AuditLog(
        actor_id=resolver_record.id,
        action=f"dispute_{payload.decision}",
        target_entity="disputes",
        target_id=str(dispute.id),
        ip_hash=hashlib.sha256(resolver_record.firebase_uid.encode("utf-8")).hexdigest()[:64],
        request_id=uuid.uuid4().hex,
        payload={
            "session_id": str(sess.id),
            "student_id": str(student.id),
            "decision": payload.decision,
            "notes": payload.resolution_notes,
        },
        created_at=now,
    )
    db.add(audit_entry)

    await db.commit()
    await db.refresh(dispute)

    return DisputeResponse(
        id=str(dispute.id),
        session_id=str(sess.id),
        course_id=str(course.id),
        course_code=course.code,
        course_name=course.name,
        student_id=str(student.id),
        student_name=student.display_name,
        roll_number=student.roll_number,
        reason=dispute.reason,
        status=dispute.status,
        resolved_by=str(dispute.resolved_by),
        resolution_notes=dispute.resolution_notes,
        created_at=dispute.created_at,
        resolved_at=dispute.resolved_at,
    )
