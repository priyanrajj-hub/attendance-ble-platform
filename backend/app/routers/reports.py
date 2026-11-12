import io
import csv
import uuid
from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.auth.rbac import AuthenticatedUser, require_role
from app.db.session import get_db
from app.models.course import Course
from app.models.user import User
from app.models.enrollment import Enrollment
from app.models.session import Session
from app.models.attendance_record import AttendanceRecord
from app.routers.roster import sanitize_formula_injection

router = APIRouter(prefix="/reports", tags=["Reports & Export"])


@router.get("/courses/{course_id}/export")
async def export_course_attendance_csv(
    course_id: str,
    current_user: AuthenticatedUser = Depends(require_role(["faculty", "admin"])),
    db: AsyncSession = Depends(get_db),
):
    """
    Exports course attendance as a sanitised CSV document.
    Protects against Formula Injection when opened in spreadsheet software.
    """
    try:
        cid = uuid.UUID(course_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid course ID format.")

    c_stmt = select(Course).where(Course.id == cid)
    c_res = await db.execute(c_stmt)
    course = c_res.scalar_one_or_none()
    if not course:
        raise HTTPException(status_code=404, detail="Course not found.")

    # Total closed/held sessions for this course
    sess_stmt = select(func.count(Session.id)).where(Session.course_id == cid)
    sess_res = await db.execute(sess_stmt)
    total_sessions = sess_res.scalar_one() or 0

    # Get active enrollments
    enr_stmt = (
        select(Enrollment, User)
        .join(User, User.id == Enrollment.student_id)
        .where(Enrollment.course_id == cid, Enrollment.status == "active")
        .order_by(User.roll_number, User.display_name)
    )
    enr_res = await db.execute(enr_stmt)
    enrolled_students = enr_res.all()

    output = io.StringIO()
    writer = csv.writer(output)

    # Write CSV Header
    writer.writerow([
        "Roll Number",
        "Student Name",
        "Institutional Email",
        "Sessions Attended",
        "Total Sessions Held",
        "Attendance Percentage",
        "Eligibility Status",
    ])

    for enrollment, student in enrolled_students:
        # Count present records
        rec_stmt = (
            select(func.count(AttendanceRecord.id))
            .join(Session, Session.id == AttendanceRecord.session_id)
            .where(
                Session.course_id == cid,
                AttendanceRecord.student_id == student.id,
                AttendanceRecord.status == "present",
            )
        )
        rec_res = await db.execute(rec_stmt)
        attended_count = rec_res.scalar_one() or 0

        pct = (attended_count / total_sessions * 100.0) if total_sessions > 0 else 100.0
        eligibility = "Eligible" if pct >= 75.0 else ("Condonable" if pct >= 65.0 else "FA Risk")

        writer.writerow([
            sanitize_formula_injection(student.roll_number or "N/A"),
            sanitize_formula_injection(student.display_name),
            sanitize_formula_injection(student.email),
            attended_count,
            total_sessions,
            f"{round(pct, 2)}%",
            eligibility,
        ])

    csv_data = output.getvalue()
    filename = f"attendance_{course.code}_{course.term}.csv"

    return Response(
        content=csv_data,
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
