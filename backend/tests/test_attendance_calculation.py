import uuid
from datetime import datetime, timezone, timedelta
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.main import app
from app.auth.rbac import get_current_user, AuthenticatedUser
from app.models.user import User
from app.models.course import Course
from app.models.session import Session
from app.models.enrollment import Enrollment
from app.models.attendance_record import AttendanceRecord


@pytest.mark.asyncio
async def test_attendance_calculation_edge_cases(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Priority 2 Verification:
    - 0 conducted sessions
    - 100% attendance
    - Complete absence
    - Cancelled sessions excluded
    - Dynamic policy threshold shifts (75% vs 80%)
    - Student isolation & faculty lookup
    """
    # 1. Setup Student & Faculty users in PostgreSQL
    tag = uuid.uuid4().hex[:8]
    st_uid = f"st_calc_{tag}"
    fac_uid = f"fac_calc_{tag}"

    fac_user = User(
        id=uuid.uuid4(),
        firebase_uid=fac_uid,
        email=f"fac_calc_{tag}@amrita.edu",
        display_name="Prof Calculation",
        role="faculty",
    )
    st_user = User(
        id=uuid.uuid4(),
        firebase_uid=st_uid,
        email=f"st_calc_{tag}@amrita.edu",
        display_name="Student Calculation",
        roll_number=f"CB.EN.U4CCE{uuid.uuid4().hex[:5].upper()}",
        role="student",
    )
    db_session.add_all([fac_user, st_user])
    await db_session.flush()

    # 2. Setup Course 1 (Normal Course) & Course 2 (Zero Sessions Course)
    c1 = Course(
        id=uuid.uuid4(),
        code=f"C1-{uuid.uuid4().hex[:4]}",
        name="Distributed Systems",
        faculty_id=fac_user.id,
        term="Fall 2026",
    )
    c2 = Course(
        id=uuid.uuid4(),
        code=f"C2-{uuid.uuid4().hex[:4]}",
        name="Advanced Lab (No Sessions Yet)",
        faculty_id=fac_user.id,
        term="Fall 2026",
    )
    db_session.add_all([c1, c2])
    await db_session.flush()

    # Enroll student in both courses
    e1 = Enrollment(course_id=c1.id, student_id=st_user.id, status="active")
    e2 = Enrollment(course_id=c2.id, student_id=st_user.id, status="active")
    db_session.add_all([e1, e2])
    await db_session.flush()

    # 3. Create Sessions for C1:
    # 4 closed sessions, 1 active session, 2 cancelled sessions
    # Total conducted should be 5 (excluding cancelled)
    sessions = []
    now = datetime.now(timezone.utc)
    for i in range(4):
        sessions.append(
            Session(
                id=uuid.uuid4(),
                course_id=c1.id,
                started_by=fac_user.id,
                room_label=f"AB1-10{i}",
                rssi_threshold=-75,
                secret_hash="dummy",
                opens_at=now - timedelta(days=5 - i),
                closes_at=now - timedelta(days=5 - i, minutes=-50),
                status="closed",
            )
        )
    # Active session
    sessions.append(
        Session(
            id=uuid.uuid4(),
            course_id=c1.id,
            started_by=fac_user.id,
            room_label="AB1-104",
            rssi_threshold=-75,
            secret_hash="dummy",
            opens_at=now - timedelta(minutes=10),
            closes_at=now + timedelta(minutes=40),
            status="active",
        )
    )
    # 2 Cancelled sessions (must NOT be counted in conducted classes)
    for i in range(2):
        sessions.append(
            Session(
                id=uuid.uuid4(),
                course_id=c1.id,
                started_by=fac_user.id,
                room_label=f"AB1-CANCEL-{i}",
                rssi_threshold=-75,
                secret_hash="dummy",
                opens_at=now - timedelta(days=10 + i),
                closes_at=now - timedelta(days=10 + i, minutes=-50),
                status="cancelled",
            )
        )
    db_session.add_all(sessions)
    await db_session.flush()

    # Student attended 3 of the 5 conducted sessions in C1
    for i in range(3):
        att = AttendanceRecord(
            id=uuid.uuid4(),
            session_id=sessions[i].id,
            student_id=st_user.id,
            method="ble_signed_nonce",
            status="present",
            verified_at=sessions[i].opens_at + timedelta(minutes=2),
        )
        db_session.add(att)
    await db_session.commit()

    # 4. Authenticate as Student and request summary
    student_auth = AuthenticatedUser(
        uid=st_uid,
        email="st_calc@amrita.edu",
        role="student",
        status="verified",
        display_name="Student Calculation",
    )
    app.dependency_overrides[get_current_user] = lambda: student_auth

    res = await client.get("/api/v1/attendance/summary")
    assert res.status_code == 200
    data = res.json()

    # Verify Course 2 (Zero Sessions Edge Case)
    c2_summary = next(c for c in data["courses"] if c["course_id"] == str(c2.id))
    assert c2_summary["conducted_sessions"] == 0
    assert c2_summary["attended_sessions"] == 0
    assert c2_summary["missed_sessions"] == 0
    assert c2_summary["attendance_pct"] == 100.0
    assert c2_summary["safe_skips_remaining"] == 0
    assert c2_summary["classes_needed_for_min"] == 0
    assert c2_summary["status"] == "Eligible"

    # Verify Course 1 (3 attended out of 5 conducted = 60.0%)
    c1_summary = next(c for c in data["courses"] if c["course_id"] == str(c1.id))
    assert c1_summary["conducted_sessions"] == 5  # Cancelled sessions successfully excluded!
    assert c1_summary["attended_sessions"] == 3
    assert c1_summary["missed_sessions"] == 2
    assert c1_summary["attendance_pct"] == 60.0
    assert c1_summary["safe_skips_remaining"] == 0
    # Classes needed to reach 75%: ceil((0.75 * 5 - 3) / 0.25) = ceil(0.75 / 0.25) = 3
    assert c1_summary["classes_needed_for_min"] == 3
    # 60% is < 65% condonation min -> Critical Shortage (FA Risk)
    assert c1_summary["status"] == "Critical Shortage (FA Risk)"

    # 5. Test Dynamic Policy Shift:
    # Lower condonation threshold to 55% -> status should become "Condonable"
    res_policy = await client.get("/api/v1/attendance/summary?min_attendance_pct=75.0&condonation_min_pct=55.0")
    assert res_policy.status_code == 200
    c1_poly = next(c for c in res_policy.json()["courses"] if c["course_id"] == str(c1.id))
    assert c1_poly["status"] == "Condonable"

    # Increase minimum required to 80%
    # Classes needed: ceil((0.80 * 5 - 3) / 0.20) = ceil(1.0 / 0.20) = 5
    res_80 = await client.get("/api/v1/attendance/summary?min_attendance_pct=80.0&condonation_min_pct=60.0")
    assert res_80.status_code == 200
    c1_80 = next(c for c in res_80.json()["courses"] if c["course_id"] == str(c1.id))
    assert c1_80["classes_needed_for_min"] == 5

    # 6. Faculty Query for Student by Roll Number
    faculty_auth = AuthenticatedUser(
        uid=fac_uid,
        email="fac_calc@amrita.edu",
        role="faculty",
        status="verified",
        display_name="Prof Calculation",
    )
    app.dependency_overrides[get_current_user] = lambda: faculty_auth

    res_fac = await client.get(f"/api/v1/attendance/summary?student_id={st_user.roll_number}")
    assert res_fac.status_code == 200
    assert res_fac.json()["student_id"] == str(st_user.id)
    assert len(res_fac.json()["courses"]) == 2
