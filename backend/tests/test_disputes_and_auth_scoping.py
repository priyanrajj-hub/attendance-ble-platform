import uuid
from datetime import datetime, timezone, timedelta
import pytest
import pytest_asyncio
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.main import app
from app.auth.rbac import AuthenticatedUser, get_current_user
from app.models.user import User
from app.models.course import Course
from app.models.enrollment import Enrollment
from app.models.session import Session
from app.models.attendance_record import AttendanceRecord
from app.models.dispute import Dispute
from app.models.override import Override
from app.models.audit_log import AuditLog
from app.db.session import get_db


@pytest_asyncio.fixture
async def dispute_test_fixture(db_session: AsyncSession):
    # Faculty 1 (Owner)
    fac1_stmt = select(User).where(User.firebase_uid == "faculty-disp-001")
    fac1 = (await db_session.execute(fac1_stmt)).scalar_one_or_none()
    if not fac1:
        fac1 = User(
            firebase_uid="faculty-disp-001",
            email="faculty1@cb.amrita.edu",
            display_name="Dr. Faculty One",
            role="faculty",
            status="verified",
        )
        db_session.add(fac1)

    # Faculty 2 (Unrelated Instructor)
    fac2_stmt = select(User).where(User.firebase_uid == "faculty-disp-002")
    fac2 = (await db_session.execute(fac2_stmt)).scalar_one_or_none()
    if not fac2:
        fac2 = User(
            firebase_uid="faculty-disp-002",
            email="faculty2@cb.amrita.edu",
            display_name="Dr. Faculty Two",
            role="faculty",
            status="verified",
        )
        db_session.add(fac2)

    # Student 1 (Enrolled)
    stud1_stmt = select(User).where(User.firebase_uid == "student-disp-001")
    stud1 = (await db_session.execute(stud1_stmt)).scalar_one_or_none()
    if not stud1:
        stud1 = User(
            firebase_uid="student-disp-001",
            email="student1@cb.students.amrita.edu",
            display_name="Student One",
            roll_number="CB.EN.U4DISP01",
            role="student",
            status="verified",
        )
        db_session.add(stud1)

    # Student 2 (Unenrolled)
    stud2_stmt = select(User).where(User.firebase_uid == "student-disp-002")
    stud2 = (await db_session.execute(stud2_stmt)).scalar_one_or_none()
    if not stud2:
        stud2 = User(
            firebase_uid="student-disp-002",
            email="student2@cb.students.amrita.edu",
            display_name="Student Two",
            roll_number="CB.EN.U4DISP02",
            role="student",
            status="verified",
        )
        db_session.add(stud2)

    await db_session.flush()

    # Course taught by Faculty 1
    course_code = f"DISP-{uuid.uuid4().hex[:6].upper()}"
    course = Course(
        code=course_code,
        name="Dispute Verification Course",
        term="Fall 2026",
        faculty_id=fac1.id,
    )
    db_session.add(course)
    await db_session.flush()

    # Enroll Student 1
    enrollment = Enrollment(
        course_id=course.id,
        student_id=stud1.id,
        status="active",
    )
    db_session.add(enrollment)

    # Session for Course
    now = datetime.now(timezone.utc)
    session = Session(
        course_id=course.id,
        started_by=fac1.id,
        room_label="Hall B-101",
        rssi_threshold=-75,
        secret_hash="ephemeral_hash_dispute_1234",
        opens_at=now - timedelta(minutes=45),
        closes_at=now + timedelta(minutes=15),
        status="active",
    )
    db_session.add(session)
    await db_session.commit()
    await db_session.refresh(course)
    await db_session.refresh(session)
    await db_session.refresh(stud1)
    await db_session.refresh(stud2)
    await db_session.refresh(fac1)
    await db_session.refresh(fac2)

    return {
        "faculty1": fac1,
        "faculty2": fac2,
        "student1": stud1,
        "student2": stud2,
        "course": course,
        "session": session,
    }


@pytest.mark.asyncio
async def test_student_submit_dispute_and_lifecycle(client: AsyncClient, dispute_test_fixture, db_session: AsyncSession):
    f = dispute_test_fixture
    stud1 = f["student1"]
    sess = f["session"]

    # Authenticate as Student 1 (Enrolled)
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(
        uid=stud1.firebase_uid,
        email=stud1.email,
        role="student",
        status="verified",
        display_name=stud1.display_name,
    )

    # 1. Submit valid dispute
    resp = await client.post(
        "/api/v1/disputes",
        json={
            "session_id": str(sess.id),
            "reason": "Bluetooth radio packet was lost due to phone restart during class.",
        },
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["session_id"] == str(sess.id)
    assert data["status"] == "pending"
    dispute_id = data["id"]

    # 2. Duplicate pending dispute rejected
    dup_resp = await client.post(
        "/api/v1/disputes",
        json={
            "session_id": str(sess.id),
            "reason": "Another dispute reason attempt.",
        },
    )
    assert dup_resp.status_code == 409

    # 3. List disputes as student (sees own dispute)
    list_resp = await client.get("/api/v1/disputes")
    assert list_resp.status_code == 200
    student_disputes = list_resp.json()
    assert any(d["id"] == dispute_id for d in student_disputes)

    # 4. Attempt resolution by Faculty 2 (Unrelated Instructor -> 403 Forbidden)
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(
        uid=f["faculty2"].firebase_uid,
        email=f["faculty2"].email,
        role="faculty",
        status="verified",
        display_name=f["faculty2"].display_name,
    )
    unauth_res = await client.post(
        f"/api/v1/disputes/{dispute_id}/resolve",
        json={"decision": "approved", "resolution_notes": "Attempt by faculty 2"},
    )
    assert unauth_res.status_code == 403

    # 5. Resolve dispute by Faculty 1 (Authorized Instructor -> 200 OK)
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(
        uid=f["faculty1"].firebase_uid,
        email=f["faculty1"].email,
        role="faculty",
        status="verified",
        display_name=f["faculty1"].display_name,
    )
    auth_res = await client.post(
        f"/api/v1/disputes/{dispute_id}/resolve",
        json={"decision": "approved", "resolution_notes": "Verified student was in seat B-12."},
    )
    assert auth_res.status_code == 200
    res_data = auth_res.json()
    assert res_data["status"] == "approved"
    assert res_data["resolution_notes"] == "Verified student was in seat B-12."

    # 6. Verify AttendanceRecord and Override were persisted in PostgreSQL
    att_stmt = select(AttendanceRecord).where(
        AttendanceRecord.session_id == sess.id,
        AttendanceRecord.student_id == stud1.id,
    )
    att_rec = (await db_session.execute(att_stmt)).scalar_one_or_none()
    assert att_rec is not None
    assert att_rec.status == "present"
    assert att_rec.method == "faculty_manual_override"
    assert "Dispute" in att_rec.override_reason

    # Verify Override row
    ovr_stmt = select(Override).where(
        Override.session_id == sess.id,
        Override.student_id == stud1.id,
    )
    ovr = (await db_session.execute(ovr_stmt)).scalar_one_or_none()
    assert ovr is not None
    assert ovr.action == "grant"

    # Verify AuditLog row
    audit_stmt = select(AuditLog).where(
        AuditLog.action == "dispute_approved",
        AuditLog.target_id == dispute_id,
    )
    audit = (await db_session.execute(audit_stmt)).scalar_one_or_none()
    assert audit is not None


@pytest.mark.asyncio
async def test_student_dispute_unenrolled_rejected(client: AsyncClient, dispute_test_fixture):
    f = dispute_test_fixture
    stud2 = f["student2"]  # Unenrolled student
    sess = f["session"]

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(
        uid=stud2.firebase_uid,
        email=stud2.email,
        role="student",
        status="verified",
        display_name=stud2.display_name,
    )

    resp = await client.post(
        "/api/v1/disputes",
        json={
            "session_id": str(sess.id),
            "reason": "Attempting dispute for course I am not enrolled in.",
        },
    )
    assert resp.status_code == 403
    assert "not enrolled" in resp.json()["detail"].lower()


@pytest.mark.asyncio
async def test_cross_faculty_authorization_defenses(client: AsyncClient, dispute_test_fixture):
    f = dispute_test_fixture
    fac2 = f["faculty2"]
    course = f["course"]
    sess = f["session"]

    # Authenticate as Faculty 2 (does NOT own course or session)
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(
        uid=fac2.firebase_uid,
        email=fac2.email,
        role="faculty",
        status="verified",
        display_name=fac2.display_name,
    )

    # 1. Course Details Defense
    c_res = await client.get(f"/api/v1/courses/{course.id}")
    assert c_res.status_code == 403
    assert "not authorized" in c_res.json()["detail"].lower()

    # 2. Reports Export Defense
    rep_res = await client.get(f"/api/v1/reports/courses/{course.id}/export")
    assert rep_res.status_code == 403
    assert "not authorized" in rep_res.json()["detail"].lower()

    # 3. Session Roster Defense
    rost_res = await client.get(f"/api/v1/sessions/{sess.id}/roster")
    assert rost_res.status_code == 403
    assert "not authorized" in rost_res.json()["detail"].lower()
