import math
import uuid
from typing import Dict, Any, List, Optional
from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import HTTPException, status

from app.models.user import User
from app.models.course import Course
from app.models.session import Session
from app.models.attendance_record import AttendanceRecord
from app.models.enrollment import Enrollment


class AttendanceCalculationService:
    """
    Authoritative Attendance Calculation Service.
    Computes rigorous course-level and institutional attendance metrics directly from PostgreSQL.
    Eliminates client-side estimation, handles zero-session courses, enforces dynamic institutional
    thresholds (e.g. 75% minimum, 65% condonation), and computes exact safe skips / classes needed.
    """

    @staticmethod
    async def get_attendance_summary(
        db: AsyncSession,
        student_id: uuid.UUID,
        min_attendance_pct: float = 75.0,
        condonation_min_pct: float = 65.0,
    ) -> Dict[str, Any]:
        if not (0.0 < min_attendance_pct <= 100.0):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="min_attendance_pct must be between 0.0 and 100.0",
            )
        if not (0.0 <= condonation_min_pct <= min_attendance_pct):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="condonation_min_pct must be between 0.0 and min_attendance_pct",
            )

        # 1. Discover all courses associated with student (active enrollments + historical records)
        enrolled_stmt = (
            select(Course)
            .join(Enrollment, Enrollment.course_id == Course.id)
            .where(Enrollment.student_id == student_id, Enrollment.status == "active")
        )
        enrolled_courses = (await db.execute(enrolled_stmt)).scalars().all()

        history_stmt = (
            select(Course)
            .join(Session, Session.course_id == Course.id)
            .join(AttendanceRecord, AttendanceRecord.session_id == Session.id)
            .where(AttendanceRecord.student_id == student_id)
        )
        history_courses = (await db.execute(history_stmt)).scalars().all()

        all_courses_dict: Dict[uuid.UUID, Course] = {}
        for c in enrolled_courses:
            all_courses_dict[c.id] = c
        for c in history_courses:
            all_courses_dict[c.id] = c

        tau = min_attendance_pct / 100.0
        kappa = condonation_min_pct / 100.0

        course_summaries: List[Dict[str, Any]] = []

        # Sort courses by code for deterministic response
        sorted_courses = sorted(all_courses_dict.values(), key=lambda c: c.code)

        for course in sorted_courses:
            # Authoritative conducted sessions (excluding cancelled)
            cond_stmt = (
                select(func.count(Session.id))
                .where(Session.course_id == course.id, Session.status != "cancelled")
            )
            conducted = (await db.execute(cond_stmt)).scalar() or 0

            # Authoritative attended sessions for this student
            att_stmt = (
                select(func.count(AttendanceRecord.id))
                .join(Session, Session.id == AttendanceRecord.session_id)
                .where(
                    Session.course_id == course.id,
                    Session.status != "cancelled",
                    AttendanceRecord.student_id == student_id,
                    AttendanceRecord.status.in_(["present", "present_override"]),
                )
            )
            attended = (await db.execute(att_stmt)).scalar() or 0
            missed = max(0, conducted - attended)

            if conducted == 0:
                pct = 100.0
                safe_skips = 0
                classes_needed = 0
                c_status = "Eligible"
            else:
                pct = round((attended / conducted) * 100.0, 2)
                if pct >= min_attendance_pct:
                    safe_skips = max(0, math.floor(round((attended - tau * conducted) / tau, 6)))
                    classes_needed = 0
                    c_status = "Eligible"
                else:
                    safe_skips = 0
                    classes_needed = max(0, math.ceil(round((tau * conducted - attended) / (1.0 - tau), 6)))
                    c_status = "Condonable" if pct >= condonation_min_pct else "Critical Shortage (FA Risk)"

            course_summaries.append({
                "course_id": str(course.id),
                "course_code": course.code,
                "course_name": course.name,
                "term": course.term,
                "conducted_sessions": conducted,
                "attended_sessions": attended,
                "missed_sessions": missed,
                "attendance_pct": pct,
                "safe_skips_remaining": safe_skips,
                "classes_needed_for_min": classes_needed,
                "status": c_status,
            })

        # Overall Institutional Totals
        total_conducted = sum(c["conducted_sessions"] for c in course_summaries)
        total_attended = sum(c["attended_sessions"] for c in course_summaries)
        total_missed = max(0, total_conducted - total_attended)

        if total_conducted == 0:
            overall_pct = 100.0
            overall_safe_skips = 0
            overall_classes_needed = 0
            overall_status = "Eligible"
        else:
            overall_pct = round((total_attended / total_conducted) * 100.0, 2)
            if overall_pct >= min_attendance_pct:
                overall_safe_skips = max(0, math.floor(round((total_attended - tau * total_conducted) / tau, 6)))
                overall_classes_needed = 0
                overall_status = "Eligible"
            else:
                overall_safe_skips = 0
                overall_classes_needed = max(0, math.ceil(round((tau * total_conducted - total_attended) / (1.0 - tau), 6)))
                overall_status = "Condonable" if overall_pct >= condonation_min_pct else "Critical Shortage (FA Risk)"

        return {
            "student_id": str(student_id),
            "institutional_policy": {
                "min_attendance_pct": min_attendance_pct,
                "condonation_min_pct": condonation_min_pct,
            },
            "overall": {
                "total_conducted": total_conducted,
                "total_attended": total_attended,
                "total_missed": total_missed,
                "attendance_pct": overall_pct,
                "safe_skips_remaining": overall_safe_skips,
                "classes_needed_for_min": overall_classes_needed,
                "status": overall_status,
            },
            "courses": course_summaries,
        }
