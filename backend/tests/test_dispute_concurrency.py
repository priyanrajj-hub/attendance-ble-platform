import asyncio
import uuid
from datetime import datetime, timezone, timedelta
import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.main import app
from app.auth.rbac import get_current_user, AuthenticatedUser
from app.models.user import User
from app.models.course import Course
from app.models.session import Session
from app.models.enrollment import Enrollment
from app.models.dispute import Dispute
from app.models.attendance_record import AttendanceRecord
from app.db.session import get_db
from tests.conftest import TestingSessionLocal


@pytest.mark.asyncio
async def test_concurrent_dispute_submission_race(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Priority 5 Test 1:
    Verifies that simultaneous duplicate dispute submissions for the same session
    and student are atomically serialized by the partial unique index and nested savepoint.
    Exactly one request must succeed with 201; the concurrent duplicate must receive 409.
    """
    tag = uuid.uuid4().hex[:8]
    fac_uid = f"fac_conc_{tag}"
    st_uid = f"st_conc_{tag}"

    fac = User(
        id=uuid.uuid4(),
        firebase_uid=fac_uid,
        email=f"fac_conc_{tag}@amrita.edu",
        display_name="Prof Concurrency",
        role="faculty",
        status="verified",
    )
    st = User(
        id=uuid.uuid4(),
        firebase_uid=st_uid,
        email=f"st_conc_{tag}@amrita.edu",
        display_name="Student Concurrency",
        roll_number=f"CB.EN.U4CCE{tag[:5].upper()}",
        role="student",
        status="verified",
    )
    db_session.add_all([fac, st])
    await db_session.flush()

    course = Course(
        id=uuid.uuid4(),
        code=f"CONC-{tag[:4].upper()}",
        name="Concurrent Systems",
        faculty_id=fac.id,
        term="Fall 2026",
    )
    db_session.add(course)
    await db_session.flush()

    enr = Enrollment(course_id=course.id, student_id=st.id, status="active")
    db_session.add(enr)
    await db_session.flush()

    now = datetime.now(timezone.utc)
    sess = Session(
        id=uuid.uuid4(),
        course_id=course.id,
        started_by=fac.id,
        room_label="AB1-Concurrency",
        rssi_threshold=-75,
        secret_hash="dummy",
        opens_at=now - timedelta(minutes=5),
        closes_at=now + timedelta(minutes=45),
        status="active",
    )
    db_session.add(sess)
    await db_session.commit()

    student_auth = AuthenticatedUser(
        uid=st_uid,
        email=st.email,
        role="student",
        status="verified",
        display_name=st.display_name,
    )
    app.dependency_overrides[get_current_user] = lambda: student_auth

    async def get_test_db():
        async with TestingSessionLocal() as session:
            yield session

    app.dependency_overrides[get_db] = get_test_db

    # Issue two concurrent dispute submissions simultaneously
    payload = {
        "session_id": str(sess.id),
        "reason": "BLE beacon signal dropped during concurrent test.",
    }

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c1, \
               AsyncClient(transport=transport, base_url="http://test") as c2:
        res1, res2 = await asyncio.gather(
            c1.post("/api/v1/disputes", json=payload),
            c2.post("/api/v1/disputes", json=payload),
        )

    statuses = [res1.status_code, res2.status_code]
    assert 201 in statuses, f"Expected at least one 201, got {statuses}"
    assert 409 in statuses, f"Expected concurrent duplicate to be rejected with 409, got {statuses}"

    # Verify database state: exactly ONE pending dispute row exists
    disp_stmt = select(Dispute).where(Dispute.session_id == sess.id, Dispute.student_id == st.id)
    disp_rows = (await db_session.execute(disp_stmt)).scalars().all()
    assert len(disp_rows) == 1
    assert disp_rows[0].status == "pending"


@pytest.mark.asyncio
async def test_concurrent_dispute_resolution_pessimistic_lock(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Priority 5 Test 2:
    Verifies that simultaneous conflicting dispute resolutions (e.g. approved vs rejected)
    are serialized by pessimistic row locking (with_for_update).
    Exactly one resolution succeeds with 200; the second is rejected with 400.
    """
    tag = uuid.uuid4().hex[:8]
    fac_uid = f"fac_res_{tag}"
    st_uid = f"st_res_{tag}"

    fac = User(
        id=uuid.uuid4(),
        firebase_uid=fac_uid,
        email=f"fac_res_{tag}@amrita.edu",
        display_name="Prof Resolver",
        role="faculty",
        status="verified",
    )
    st = User(
        id=uuid.uuid4(),
        firebase_uid=st_uid,
        email=f"st_res_{tag}@amrita.edu",
        display_name="Student Resolver",
        roll_number=f"CB.EN.U4CCE{tag[:5].upper()}",
        role="student",
        status="verified",
    )
    db_session.add_all([fac, st])
    await db_session.flush()

    course = Course(
        id=uuid.uuid4(),
        code=f"RES-{tag[:4].upper()}",
        name="Resolution Lab",
        faculty_id=fac.id,
        term="Fall 2026",
    )
    db_session.add(course)
    await db_session.flush()

    sess = Session(
        id=uuid.uuid4(),
        course_id=course.id,
        started_by=fac.id,
        room_label="AB2-202",
        rssi_threshold=-75,
        secret_hash="dummy",
        opens_at=datetime.now(timezone.utc) - timedelta(minutes=10),
        closes_at=datetime.now(timezone.utc) + timedelta(minutes=40),
        status="active",
    )
    db_session.add(sess)
    await db_session.flush()

    dispute = Dispute(
        id=uuid.uuid4(),
        session_id=sess.id,
        student_id=st.id,
        reason="Missed check-in window due to phone reboot.",
        status="pending",
    )
    db_session.add(dispute)
    await db_session.commit()

    faculty_auth = AuthenticatedUser(
        uid=fac_uid,
        email=fac.email,
        role="faculty",
        status="verified",
        display_name=fac.display_name,
    )
    app.dependency_overrides[get_current_user] = lambda: faculty_auth

    async def get_test_db():
        async with TestingSessionLocal() as session:
            yield session

    app.dependency_overrides[get_db] = get_test_db

    # Simultaneous resolution attempts: one approves, one rejects
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c1, \
               AsyncClient(transport=transport, base_url="http://test") as c2:
        res1, res2 = await asyncio.gather(
            c1.post(f"/api/v1/disputes/{dispute.id}/resolve", json={"decision": "approved", "resolution_notes": "Granted"}),
            c2.post(f"/api/v1/disputes/{dispute.id}/resolve", json={"decision": "rejected", "resolution_notes": "Denied"}),
        )

    statuses = [res1.status_code, res2.status_code]
    assert 200 in statuses, f"Expected one 200 OK resolution, got {statuses}"
    assert 400 in statuses, f"Expected second concurrent resolution to fail with 400, got {statuses}"

    # Verify final dispute status in DB
    await db_session.refresh(dispute)
    assert dispute.status in ("approved", "rejected")
    assert dispute.resolved_at is not None
