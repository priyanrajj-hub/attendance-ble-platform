import pytest
import uuid
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.main import app
from app.auth.rbac import get_current_user, AuthenticatedUser
from app.auth.firebase_auth import verify_firebase_id_token
from app.ai.agent_client import AttendancePolicyEngine
from app.models.user import User
from app.models.course import Course
from app.models.session import Session
from app.models.enrollment import Enrollment
from datetime import datetime, timezone, timedelta


def test_amrita_policy_engine_calculations():
    """
    Verifies policy calculation oracle for 75% Amrita minimum attendance.
    """
    # Case 1: 18 out of 20 = 90% (Safe)
    calc1 = AttendancePolicyEngine.calculate_margin(18, 20)
    assert calc1["percentage"] == 90.0
    assert calc1["status"] == "Safe"
    assert calc1["safe_skips"] >= 1

    # Case 2: 14 out of 20 = 70% (Shortage - Condonable)
    calc2 = AttendancePolicyEngine.calculate_margin(14, 20)
    assert calc2["percentage"] == 70.0
    assert "Condonation Eligible" in calc2["status"]
    assert calc2["classes_needed"] > 0

    # Case 3: 10 out of 20 = 50% (Critical Shortage - FA Risk)
    calc3 = AttendancePolicyEngine.calculate_margin(10, 20)
    assert calc3["percentage"] == 50.0
    assert "FA Risk" in calc3["status"]


@pytest.mark.asyncio
async def test_proximity_checkin_requires_auth(client: AsyncClient):
    """
    SEC-02 Regression: Client cannot directly commit attendance without authentication.
    Unauthenticated check-in requests must be rejected with HTTP 401 Unauthorized.
    """
    payload = {
        "session_id": "00000000-0000-0000-0000-000000000001",
        "ephemeral_nonce": "abcdef0123456789",
        "observed_rssi": -65,
    }
    res = await client.post("/api/v1/attendance/check-in", json=payload)
    assert res.status_code == 401


@pytest.mark.asyncio
async def test_sec03_no_student_endpoint_returns_session_secret(
    client: AsyncClient, mock_student_user: AuthenticatedUser, db_session: AsyncSession
):
    """
    SEC-03 Regression Proof:
    Confirms that no student-accessible endpoint returns session secrets, hashes, or ephemeral tokens.
    """
    app.dependency_overrides[get_current_user] = lambda: mock_student_user

    # 1. Setup Student, Faculty, Course, Active Session, and Enrollment in PostgreSQL
    uid_suf = uuid.uuid4().hex[:8]
    s_stmt = select(User).where(User.firebase_uid == mock_student_user.uid)
    s_res = await db_session.execute(s_stmt)
    student = s_res.scalar_one_or_none()
    if not student:
        student = User(
            firebase_uid=mock_student_user.uid,
            email=mock_student_user.email,
            display_name="Student Test",
            role="student",
            status="verified",
        )
        db_session.add(student)
        await db_session.flush()

    faculty = User(
        firebase_uid=f"fac-sec-{uid_suf}",
        email=f"fac_{uid_suf}@ch.amrita.edu",
        display_name="Dr. Security",
        role="faculty",
        status="verified",
    )
    db_session.add(faculty)
    await db_session.flush()

    course = Course(
        code=f"SEC{uid_suf[:3].upper()}",
        name="Network Security",
        term="Fall 2026",
        faculty_id=faculty.id,
    )
    db_session.add(course)
    await db_session.flush()

    enrollment = Enrollment(
        course_id=course.id,
        student_id=student.id,
        status="active",
    )
    db_session.add(enrollment)

    active_session = Session(
        course_id=course.id,
        started_by=faculty.id,
        room_label="Lab 301",
        rssi_threshold=-75,
        secret_hash="sensitive_super_secret_sha256_hash_here",
        opens_at=datetime.now(timezone.utc),
        closes_at=datetime.now(timezone.utc) + timedelta(minutes=45),
        status="active",
    )
    db_session.add(active_session)
    await db_session.commit()

    # 2. Student requests active sessions
    res = await client.get("/api/v1/sessions/active")
    assert res.status_code == 200
    sessions_data = res.json()
    assert len(sessions_data) >= 1

    # 3. Verify ZERO leakage of secrets in student payload
    for s in sessions_data:
        assert "secret_hash" not in s, "CRITICAL LEAK: secret_hash exposed to student!"
        assert "secret" not in s, "CRITICAL LEAK: secret exposed to student!"
        assert "ephemeral_token" not in s, "CRITICAL LEAK: ephemeral_token exposed to student!"
        assert s.get("room_label") == "Lab 301"

    app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_auth_profile_sync_zero_trust_role_assignment(
    client: AsyncClient, db_session: AsyncSession, monkeypatch
):
    """
    Zero-Trust Role Assignment Regression:
    Ensures that when a user calls /sync-profile:
    1. Role is strictly derived from verified email domain in Firebase ID token.
    2. Malicious role/status injected in request payload is completely ignored.
    3. Status is strictly initialized to pending_verification.
    """
    test_uid = f"uid-{uuid.uuid4().hex[:12]}"
    test_email = f"cb.en.u4cse22{uuid.uuid4().hex[:4]}@ch.students.amrita.edu"

    # Mock token verification output (simulating valid Firebase ID token)
    def mock_verify_token(token: str):
        return {
            "uid": test_uid,
            "email": test_email,
            "email_verified": True,
            "name": "Arun Student",
        }

    monkeypatch.setattr("app.routers.auth.verify_firebase_id_token", mock_verify_token)

    # Malicious client sends role=admin, status=verified
    malicious_payload = {
        "display_name": "Arun Student",
        "roll_number": "CSE22055",
        "role": "admin",
        "status": "verified",
    }

    headers = {"Authorization": "Bearer fake-test-token"}
    res = await client.post("/api/v1/auth/sync-profile", json=malicious_payload, headers=headers)
    assert res.status_code == 200
    data = res.json()

    # Verify that the server assigned student and pending_verification, ignoring client spoofing
    assert data["uid"] == test_uid
    assert data["email"] == test_email
    assert data["role"] == "student", "CRITICAL VULNERABILITY: Server accepted client-supplied role!"
    assert data["status"] == "pending_verification", "CRITICAL VULNERABILITY: Server accepted client-supplied verified status!"


@pytest.mark.asyncio
async def test_auth_profile_sync_unauthorized_domain_rejected(
    client: AsyncClient, monkeypatch
):
    """
    Ensures non-institutional domains (e.g. gmail.com) are rejected with HTTP 403.
    """
    def mock_verify_token(token: str):
        return {
            "uid": "uid-gmail-user",
            "email": "hacker@gmail.com",
            "email_verified": True,
        }

    monkeypatch.setattr("app.routers.auth.verify_firebase_id_token", mock_verify_token)

    headers = {"Authorization": "Bearer fake-test-token"}
    res = await client.post("/api/v1/auth/sync-profile", json={}, headers=headers)
    assert res.status_code == 403
    assert "not authorized" in res.json()["detail"]


@pytest.mark.asyncio
async def test_ai_agent_query_endpoint(
    client: AsyncClient, mock_student_user: AuthenticatedUser
):
    """
    Verifies AI query endpoint uses local deterministic policy engine without external leakage.
    """
    app.dependency_overrides[get_current_user] = lambda: mock_student_user

    res = await client.post(
        "/api/v1/ai/query",
        json={
            "prompt": "What is the minimum attendance required for semester exams?",
            "attended_classes": 14,
            "total_classes": 20,
        },
    )
    assert res.status_code == 200
    data = res.json()
    assert "75%" in data["response"]
    assert data["source"] == "amrita_policy_engine_v1_local"
    assert data["calculation"] is not None
    assert data["calculation"]["percentage"] == 70.0

    app.dependency_overrides.clear()
