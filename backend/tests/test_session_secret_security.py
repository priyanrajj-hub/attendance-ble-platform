import uuid
from datetime import datetime, timezone
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
from app.services.session_crypto import SessionCrypto
from app.services.challenge_service import ChallengeService


@pytest.mark.asyncio
async def test_session_secret_at_rest_envelope_encryption_and_zero_leakage(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Priority 3 Test:
    1. Verifies sessions.secret_hash stores AES-256-GCM envelope ciphertext ('enc:...'), NEVER plaintext.
    2. Verifies ChallengeService decrypts secret in memory and validates challenges.
    3. Negative tests: Ensures session secrets NEVER leak in student endpoints or active session listings.
    """
    tag = uuid.uuid4().hex[:8]
    fac_uid = f"fac_crypto_{tag}"
    st_uid = f"st_crypto_{tag}"

    fac_user = User(
        id=uuid.uuid4(),
        firebase_uid=fac_uid,
        email=f"fac_crypto_{tag}@amrita.edu",
        display_name="Prof Cryptographer",
        role="faculty",
        status="verified",
    )
    st_user = User(
        id=uuid.uuid4(),
        firebase_uid=st_uid,
        email=f"st_crypto_{tag}@amrita.edu",
        display_name="Student Cryptography",
        roll_number=f"CB.EN.U4CCE{tag[:5].upper()}",
        role="student",
        status="verified",
    )
    db_session.add_all([fac_user, st_user])
    await db_session.flush()

    course = Course(
        id=uuid.uuid4(),
        code=f"SEC-{tag[:4].upper()}",
        name="Applied Cryptography",
        faculty_id=fac_user.id,
        term="Fall 2026",
    )
    db_session.add(course)
    await db_session.flush()

    enrollment = Enrollment(
        course_id=course.id,
        student_id=st_user.id,
        status="active",
    )
    db_session.add(enrollment)
    await db_session.commit()

    faculty_auth = AuthenticatedUser(
        uid=fac_uid,
        email=fac_user.email,
        role="faculty",
        status="verified",
        display_name="Prof Cryptographer",
    )
    app.dependency_overrides[get_current_user] = lambda: faculty_auth

    # 1. Start Session via API
    start_res = await client.post(
        "/api/v1/sessions/start",
        json={
            "course_id": str(course.id),
            "room_label": "AB3-301",
            "duration_minutes": 50,
            "rssi_threshold": -75,
        },
    )
    assert start_res.status_code == 201
    start_data = start_res.json()
    session_id = start_data["id"]
    ephemeral_token = start_data["ephemeral_token"]
    assert len(ephemeral_token) == 64

    # 2. Inspect Database Row directly: Must NOT contain plaintext ephemeral_token
    session_stmt = select(Session).where(Session.id == uuid.UUID(session_id))
    db_sess = (await db_session.execute(session_stmt)).scalar_one()

    assert db_sess.secret_hash != ephemeral_token, "SECURITY CRITICAL: Plaintext secret stored at rest in PostgreSQL!"
    assert db_sess.secret_hash.startswith("enc:"), "Encrypted secret must follow envelope format 'enc:<nonce>:<ct>'"
    assert len(db_sess.secret_hash) <= 128, "Encrypted string must fit inside VARCHAR(128)"

    # Verify SessionCrypto decrypts correctly in memory
    decrypted = SessionCrypto.decrypt_session_secret(db_sess.secret_hash)
    assert decrypted == ephemeral_token

    # 3. Verify ChallengeService validates challenge derived from plaintext token
    now = datetime.now(timezone.utc)
    current_step = int(now.timestamp()) // ChallengeService.ROTATION_PERIOD_SECONDS
    valid_challenge = ChallengeService.compute_challenge(ephemeral_token, session_id, current_step)

    is_valid = await ChallengeService.verify_challenge(
        db=db_session,
        session=db_sess,
        submitted_nonce=valid_challenge,
    )
    assert is_valid is True, "Challenge verification failed with decrypted session secret"

    # 4. Leakage Negative Test: Student Endpoints MUST NEVER disclose secret_hash or ephemeral_token
    student_auth = AuthenticatedUser(
        uid=st_uid,
        email=st_user.email,
        role="student",
        status="verified",
        display_name="Student Cryptography",
    )
    app.dependency_overrides[get_current_user] = lambda: student_auth

    # A. Active sessions listing
    active_res = await client.get("/api/v1/sessions/active")
    assert active_res.status_code == 200
    active_sessions = active_res.json()
    this_session = next((s for s in active_sessions if s["id"] == session_id), None)
    assert this_session is not None
    assert "secret_hash" not in this_session
    assert "ephemeral_token" not in this_session

    # B. Specific session lookup
    lookup_res = await client.get(f"/api/v1/sessions/{session_id}")
    assert lookup_res.status_code == 200
    lookup_data = lookup_res.json()
    assert "secret_hash" not in lookup_data
    assert "ephemeral_token" not in lookup_data
