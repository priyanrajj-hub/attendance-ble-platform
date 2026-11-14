import uuid
import hmac
import hashlib
from datetime import datetime, timezone, timedelta
import pytest
import pytest_asyncio
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import hashes, serialization

from app.main import app
from app.auth.rbac import AuthenticatedUser, get_current_user
from app.models.user import User
from app.models.course import Course
from app.models.enrollment import Enrollment
from app.models.session import Session
from app.models.device import Device
from app.models.attendance_record import AttendanceRecord
from app.models.override import Override
from app.models.audit_log import AuditLog
from app.models.consumed_nonce import ConsumedNonce
from app.services.challenge_service import ChallengeService


@pytest.fixture
def student_auth_user() -> AuthenticatedUser:
    return AuthenticatedUser(
        uid="student-e2e-001",
        email="student.e2e@cb.students.amrita.edu",
        role="student",
        status="verified",
        display_name="E2E Test Student",
    )


@pytest.fixture
def ec_keypair():
    priv = ec.generate_private_key(ec.SECP256R1())
    pub = priv.public_key()
    pem = pub.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode("utf-8")
    return priv, pem


@pytest_asyncio.fixture
async def e2e_setup(db_session: AsyncSession, student_auth_user: AuthenticatedUser):
    # 1. Faculty
    faculty_stmt = select(User).where(User.firebase_uid == "faculty-e2e-001")
    f_res = await db_session.execute(faculty_stmt)
    faculty = f_res.scalar_one_or_none()
    if not faculty:
        faculty = User(
            firebase_uid="faculty-e2e-001",
            email="faculty.e2e@cb.amrita.edu",
            role="faculty",
            status="verified",
            display_name="Dr. E2E Faculty",
        )
        db_session.add(faculty)
        await db_session.flush()

    # 2. Student
    student_stmt = select(User).where(User.firebase_uid == student_auth_user.uid)
    s_res = await db_session.execute(student_stmt)
    student = s_res.scalar_one_or_none()
    if not student:
        student = User(
            firebase_uid=student_auth_user.uid,
            email=student_auth_user.email,
            role="student",
            status="verified",
            display_name=student_auth_user.display_name,
            roll_number="CB.EN.U4E2E001",
        )
        db_session.add(student)
        await db_session.flush()

    # 3. Course
    course_code = f"E2E-{uuid.uuid4().hex[:6].upper()}"
    course = Course(
        code=course_code,
        name="End-to-End Cryptographic BLE Verification",
        faculty_id=faculty.id,
        term="Fall 2026",
    )
    db_session.add(course)
    await db_session.flush()

    # 4. Enrollment
    enrollment = Enrollment(
        course_id=course.id,
        student_id=student.id,
        status="active",
    )
    db_session.add(enrollment)

    # 5. Active Session
    ephemeral_secret = "e2e_session_secret_hash_value_1234567890abcdef"
    now = datetime.now(timezone.utc)
    session = Session(
        course_id=course.id,
        started_by=faculty.id,
        room_label="E2E-Lab-401",
        rssi_threshold=-75,
        secret_hash=ephemeral_secret,
        opens_at=now - timedelta(minutes=1),
        closes_at=now + timedelta(minutes=45),
        status="active",
    )
    db_session.add(session)
    await db_session.commit()
    await db_session.refresh(session)
    await db_session.refresh(student)

    return {
        "faculty": faculty,
        "student": student,
        "course": course,
        "session": session,
    }


@pytest.mark.asyncio
async def test_device_registration_and_signature_e2e(
    client: AsyncClient,
    db_session: AsyncSession,
    student_auth_user: AuthenticatedUser,
    e2e_setup: dict,
    ec_keypair,
):
    app.dependency_overrides[get_current_user] = lambda: student_auth_user
    priv_key, pub_pem = ec_keypair

    # 1. Register Device
    reg_res = await client.post(
        "/api/v1/devices/register",
        json={
            "public_key_pem": pub_pem,
            "platform": "android",
            "device_model": "Pixel 8 Pro",
            "os_version": "Android 15",
        },
    )
    assert reg_res.status_code == 201, reg_res.text
    dev_data = reg_res.json()
    fingerprint = dev_data["public_key_fingerprint"]
    assert len(fingerprint) == 64

    # 2. Derive valid 128-bit rotating challenge code (session-bound)
    sess = e2e_setup["session"]
    now = datetime.now(timezone.utc)
    step = int(now.timestamp()) // ChallengeService.ROTATION_PERIOD_SECONDS
    code = ChallengeService.compute_challenge(sess.secret_hash, str(sess.id), step)

    # 3. Create digital signature over session_id:code:client_timestamp
    timestamp = int(now.timestamp() * 1000)
    canonical_msg = f"{sess.id}:{code}:{timestamp}".encode("utf-8")
    sig_bytes = priv_key.sign(canonical_msg, ec.ECDSA(hashes.SHA256()))
    sig_hex = sig_bytes.hex()

    # 4. Submit Check-In
    checkin_res = await client.post(
        "/api/v1/attendance/check-in",
        json={
            "session_id": str(sess.id),
            "ephemeral_nonce": code,
            "observed_rssi": -65,
            "client_timestamp": timestamp,
            "public_key_fingerprint": fingerprint,
            "signature": sig_hex,
        },
    )
    assert checkin_res.status_code == 200, checkin_res.text
    result = checkin_res.json()
    assert result["already_marked"] is False
    assert result["signature_verified"] is True
    assert result["status"] == "present"

    # 5. Verify PostgreSQL record persistence
    att_stmt = select(AttendanceRecord).where(
        AttendanceRecord.session_id == sess.id,
        AttendanceRecord.student_id == e2e_setup["student"].id,
    )
    att_res = await db_session.execute(att_stmt)
    rec = att_res.scalar_one()
    assert rec.signature_verified is True
    assert rec.method == "ble_signed_nonce"
    assert rec.rssi_observed == -65

    # 6. Replay Check-In (Idempotency verification)
    replay_res = await client.post(
        "/api/v1/attendance/check-in",
        json={
            "session_id": str(sess.id),
            "ephemeral_nonce": code,
            "observed_rssi": -65,
            "client_timestamp": timestamp,
            "public_key_fingerprint": fingerprint,
            "signature": sig_hex,
        },
    )
    assert replay_res.status_code == 200
    replay_data = replay_res.json()
    assert replay_data["already_marked"] is True
    assert replay_data["attendance_id"] == str(rec.id)

    # 7. Verify My-History Endpoint (Student source of truth)
    hist_res = await client.get("/api/v1/attendance/my-history")
    assert hist_res.status_code == 200
    hist_items = hist_res.json()
    assert len(hist_items) >= 1
    assert hist_items[0]["session_id"] == str(sess.id)
    assert hist_items[0]["status"] == "present"

    # 8. Verify Session Roster Endpoint (Faculty source of truth)
    faculty_user = AuthenticatedUser(
        uid=e2e_setup["faculty"].firebase_uid,
        email=e2e_setup["faculty"].email,
        role="faculty",
        status="verified",
        display_name="Dr. E2E Faculty",
    )
    app.dependency_overrides[get_current_user] = lambda: faculty_user
    roster_res = await client.get(f"/api/v1/sessions/{sess.id}/roster")
    assert roster_res.status_code == 200
    roster_items = roster_res.json()
    assert len(roster_items) >= 1
    student_roster = next(r for r in roster_items if r["student_uid"] == student_auth_user.uid)
    assert student_roster["is_present"] is True
    assert student_roster["status"] == "present"


@pytest.mark.asyncio
async def test_forged_device_signature_rejected(
    client: AsyncClient,
    student_auth_user: AuthenticatedUser,
    e2e_setup: dict,
    ec_keypair,
):
    app.dependency_overrides[get_current_user] = lambda: student_auth_user
    priv_key, pub_pem = ec_keypair

    # Register valid device
    reg_res = await client.post(
        "/api/v1/devices/register",
        json={"public_key_pem": pub_pem, "platform": "android"},
    )
    fingerprint = reg_res.json()["public_key_fingerprint"]

    sess = e2e_setup["session"]
    now = datetime.now(timezone.utc)
    step = int(now.timestamp()) // ChallengeService.ROTATION_PERIOD_SECONDS
    code = ChallengeService.compute_challenge(sess.secret_hash, str(sess.id), step)

    # Sign with a completely different foreign private key
    foreign_priv = ec.generate_private_key(ec.SECP256R1())
    timestamp = int(now.timestamp() * 1000)
    canonical_msg = f"{sess.id}:{code}:{timestamp}".encode("utf-8")
    forged_sig = foreign_priv.sign(canonical_msg, ec.ECDSA(hashes.SHA256())).hex()

    # Submit with forged signature
    res = await client.post(
        "/api/v1/attendance/check-in",
        json={
            "session_id": str(sess.id),
            "ephemeral_nonce": code,
            "observed_rssi": -70,
            "client_timestamp": timestamp,
            "public_key_fingerprint": fingerprint,
            "signature": forged_sig,
        },
    )
    assert res.status_code == 403
    assert "Cryptographic device signature verification failed" in res.json()["detail"]


@pytest.mark.asyncio
async def test_missing_device_signature_rejected(
    client: AsyncClient,
    student_auth_user: AuthenticatedUser,
    e2e_setup: dict,
):
    app.dependency_overrides[get_current_user] = lambda: student_auth_user

    sess = e2e_setup["session"]
    now = datetime.now(timezone.utc)
    step = int(now.timestamp()) // ChallengeService.ROTATION_PERIOD_SECONDS
    code = ChallengeService.compute_challenge(sess.secret_hash, str(sess.id), step)

    # Submit valid challenge code without signature
    res = await client.post(
        "/api/v1/attendance/check-in",
        json={
            "session_id": str(sess.id),
            "ephemeral_nonce": code,
            "observed_rssi": -70,
        },
    )
    assert res.status_code == 400
    assert "Cryptographic device signature is required" in res.json()["detail"]


@pytest.mark.asyncio
async def test_expired_rotating_code_rejected(
    client: AsyncClient,
    student_auth_user: AuthenticatedUser,
    e2e_setup: dict,
):
    app.dependency_overrides[get_current_user] = lambda: student_auth_user

    sess = e2e_setup["session"]
    now = datetime.now(timezone.utc)
    # Stale step from 10 minutes ago
    stale_step = (int(now.timestamp()) - 600) // ChallengeService.ROTATION_PERIOD_SECONDS
    stale_code = ChallengeService.compute_challenge(sess.secret_hash, str(sess.id), stale_step)

    res = await client.post(
        "/api/v1/attendance/check-in",
        json={
            "session_id": str(sess.id),
            "ephemeral_nonce": stale_code,
            "observed_rssi": -70,
        },
    )
    assert res.status_code == 403
    assert "Invalid or expired BLE proximity nonce challenge" in res.json()["detail"]


@pytest.mark.asyncio
async def test_unenrolled_student_rejected(
    client: AsyncClient,
    db_session: AsyncSession,
    e2e_setup: dict,
):
    unenrolled_user = AuthenticatedUser(
        uid="student-unenrolled-099",
        email="unenrolled@cb.students.amrita.edu",
        role="student",
        status="verified",
        display_name="Unenrolled Student",
    )
    u_stmt = select(User).where(User.firebase_uid == unenrolled_user.uid)
    u_res = await db_session.execute(u_stmt)
    u = u_res.scalar_one_or_none()
    if not u:
        u = User(
            firebase_uid=unenrolled_user.uid,
            email=unenrolled_user.email,
            role="student",
            status="verified",
            display_name=unenrolled_user.display_name,
        )
        db_session.add(u)
        await db_session.commit()

    app.dependency_overrides[get_current_user] = lambda: unenrolled_user

    sess = e2e_setup["session"]
    now = datetime.now(timezone.utc)
    step = int(now.timestamp()) // ChallengeService.ROTATION_PERIOD_SECONDS
    code = ChallengeService.compute_challenge(sess.secret_hash, str(sess.id), step)

    res = await client.post(
        "/api/v1/attendance/check-in",
        json={
            "session_id": str(sess.id),
            "ephemeral_nonce": code,
            "observed_rssi": -70,
        },
    )
    assert res.status_code == 403
    assert "Student is not enrolled in this course" in res.json()["detail"]


@pytest.mark.asyncio
async def test_faculty_manual_override_success(
    client: AsyncClient,
    db_session: AsyncSession,
    e2e_setup: dict,
):
    faculty = e2e_setup["faculty"]
    student = e2e_setup["student"]
    sess = e2e_setup["session"]

    faculty_auth_user = AuthenticatedUser(
        uid=faculty.firebase_uid,
        email=faculty.email,
        role="faculty",
        status="verified",
        display_name=faculty.display_name,
    )
    app.dependency_overrides[get_current_user] = lambda: faculty_auth_user

    res = await client.post(
        f"/api/v1/sessions/{sess.id}/manual-override",
        json={
            "student_id": student.firebase_uid,
            "reason": "BLE radio damaged on student phone, manually verified in room.",
        },
    )
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "success"
    assert data["method"] == "faculty_manual_override"

    # Verify persisted in PostgreSQL
    att_stmt = select(AttendanceRecord).where(
        AttendanceRecord.session_id == sess.id,
        AttendanceRecord.student_id == student.id,
    )
    att_res = await db_session.execute(att_stmt)
    rec = att_res.scalar_one_or_none()
    assert rec is not None
    assert rec.method == "faculty_manual_override"
    assert rec.signature_verified is False
    assert rec.status == "present"


@pytest.mark.asyncio
async def test_faculty_manual_override_short_reason_rejected(
    client: AsyncClient,
    e2e_setup: dict,
):
    faculty = e2e_setup["faculty"]
    student = e2e_setup["student"]
    sess = e2e_setup["session"]

    faculty_auth_user = AuthenticatedUser(
        uid=faculty.firebase_uid,
        email=faculty.email,
        role="faculty",
        status="verified",
        display_name=faculty.display_name,
    )
    app.dependency_overrides[get_current_user] = lambda: faculty_auth_user

    res = await client.post(
        f"/api/v1/sessions/{sess.id}/manual-override",
        json={
            "student_id": student.firebase_uid,
            "reason": "ok",  # Less than 3 characters
        },
    )
    assert res.status_code == 400
    assert "at least 3 characters" in res.json()["detail"]


@pytest.mark.asyncio
async def test_faculty_manual_override_unauthorized_for_other_faculty(
    client: AsyncClient,
    db_session: AsyncSession,
    e2e_setup: dict,
):
    other_uid = f"fac-intruder-{uuid.uuid4().hex[:8]}"
    other_fac = User(
        firebase_uid=other_uid,
        email=f"{other_uid}@cb.amrita.edu",
        role="faculty",
        status="verified",
        display_name="Other Faculty",
    )
    db_session.add(other_fac)
    await db_session.commit()

    other_auth_user = AuthenticatedUser(
        uid=other_fac.firebase_uid,
        email=other_fac.email,
        role="faculty",
        status="verified",
        display_name=other_fac.display_name,
    )
    app.dependency_overrides[get_current_user] = lambda: other_auth_user

    sess = e2e_setup["session"]
    student = e2e_setup["student"]

    res = await client.post(
        f"/api/v1/sessions/{sess.id}/manual-override",
        json={
            "student_id": student.firebase_uid,
            "reason": "Unauthorized override attempt",
        },
    )
    assert res.status_code == 403


@pytest.mark.asyncio
async def test_weak_rssi_below_threshold_rejected(
    client: AsyncClient,
    e2e_setup: dict,
    student_auth_user: AuthenticatedUser,
    ec_keypair: tuple,
):
    priv_key, pub_pem = ec_keypair
    app.dependency_overrides[get_current_user] = lambda: student_auth_user

    # Register device
    reg_res = await client.post(
        "/api/v1/devices/register",
        json={
            "public_key_pem": pub_pem,
            "platform": "android",
            "device_model": "Test Phone",
            "os_version": "Android 14",
        },
    )
    assert reg_res.status_code == 201

    sess = e2e_setup["session"]  # rssi_threshold is -75
    now = datetime.now(timezone.utc)
    step = int(now.timestamp()) // ChallengeService.ROTATION_PERIOD_SECONDS
    code = ChallengeService.compute_challenge(sess.secret_hash, str(sess.id), step)

    now_ms = int(now.timestamp() * 1000)
    canonical = f"{sess.id}:{code}:{now_ms}".encode("utf-8")
    sig = priv_key.sign(canonical, ec.ECDSA(hashes.SHA256()))

    # Weak RSSI: -85 dBm is weaker than session threshold -75 dBm
    res = await client.post(
        "/api/v1/attendance/check-in",
        json={
            "session_id": str(sess.id),
            "ephemeral_nonce": code,
            "observed_rssi": -85,
            "client_timestamp": now_ms,
            "signature": sig.hex(),
        },
    )
    assert res.status_code == 403
    assert "proximity threshold" in res.json()["detail"]


@pytest.mark.asyncio
async def test_invalid_rssi_range_rejected(
    client: AsyncClient,
    e2e_setup: dict,
    student_auth_user: AuthenticatedUser,
):
    app.dependency_overrides[get_current_user] = lambda: student_auth_user
    sess = e2e_setup["session"]

    # Absurd positive RSSI: +10 dBm
    res = await client.post(
        "/api/v1/attendance/check-in",
        json={
            "session_id": str(sess.id),
            "ephemeral_nonce": "12345678123456781234567812345678",
            "observed_rssi": 10,
        },
    )
    assert res.status_code == 400
    assert "invalid" in res.json()["detail"].lower()


@pytest.mark.asyncio
async def test_future_client_timestamp_rejected(
    client: AsyncClient,
    e2e_setup: dict,
    student_auth_user: AuthenticatedUser,
    ec_keypair: tuple,
):
    priv_key, pub_pem = ec_keypair
    app.dependency_overrides[get_current_user] = lambda: student_auth_user

    sess = e2e_setup["session"]
    now = datetime.now(timezone.utc)
    step = int(now.timestamp()) // ChallengeService.ROTATION_PERIOD_SECONDS
    code = ChallengeService.compute_challenge(sess.secret_hash, str(sess.id), step)

    # 10 minutes in the future
    future_ms = int((now + timedelta(minutes=10)).timestamp() * 1000)

    res = await client.post(
        "/api/v1/attendance/check-in",
        json={
            "session_id": str(sess.id),
            "ephemeral_nonce": code,
            "observed_rssi": -65,
            "client_timestamp": future_ms,
            "signature": "fake_sig",
        },
    )
    assert res.status_code == 400
    assert "future" in res.json()["detail"].lower()


@pytest.mark.asyncio
async def test_manual_override_audit_trail_persisted_in_postgresql(
    client: AsyncClient,
    db_session: AsyncSession,
    e2e_setup: dict,
):
    faculty = e2e_setup["faculty"]
    student = e2e_setup["student"]
    sess = e2e_setup["session"]

    faculty_auth_user = AuthenticatedUser(
        uid=faculty.firebase_uid,
        email=faculty.email,
        role="faculty",
        status="verified",
        display_name=faculty.display_name,
    )
    app.dependency_overrides[get_current_user] = lambda: faculty_auth_user

    reason = "Student device Bluetooth radio damaged; confirmed seated in row 3."
    res = await client.post(
        f"/api/v1/sessions/{sess.id}/manual-override",
        json={
            "student_id": student.firebase_uid,
            "reason": reason,
        },
    )
    assert res.status_code == 200

    # 1. Verify AttendanceRecord in PostgreSQL retains reason and marked_by
    att_stmt = select(AttendanceRecord).where(
        AttendanceRecord.session_id == sess.id,
        AttendanceRecord.student_id == student.id,
    )
    att_res = await db_session.execute(att_stmt)
    rec = att_res.scalar_one_or_none()
    assert rec is not None
    assert rec.override_reason == reason
    assert rec.marked_by == faculty.id
    assert rec.method == "faculty_manual_override"

    # 2. Verify formal Override audit record
    ov_stmt = select(Override).where(
        Override.session_id == sess.id,
        Override.student_id == student.id,
    )
    ov_res = await db_session.execute(ov_stmt)
    ov = ov_res.scalar_one_or_none()
    assert ov is not None
    assert ov.reason == reason
    assert ov.actor_id == faculty.id
    assert ov.action == "grant"

    # 3. Verify security AuditLog entry
    audit_stmt = select(AuditLog).where(
        AuditLog.action == "manual_override",
        AuditLog.target_id == str(rec.id),
    )
    audit_res = await db_session.execute(audit_stmt)
    audit = audit_res.scalar_one_or_none()
    assert audit is not None
    assert audit.payload["reason"] == reason


@pytest.mark.asyncio
async def test_device_attestation_challenge_and_verification(
    client: AsyncClient,
    student_auth_user: AuthenticatedUser,
    ec_keypair: tuple,
):
    priv_key, pub_pem = ec_keypair
    app.dependency_overrides[get_current_user] = lambda: student_auth_user

    # 1. Request attestation challenge
    chall_res = await client.post("/api/v1/devices/attestation-challenge")
    assert chall_res.status_code == 201
    chall_data = chall_res.json()
    assert "challenge" in chall_data
    assert len(chall_data["challenge"]) == 64

    # 2. Register device with invalid challenge -> rejected
    bad_res = await client.post(
        "/api/v1/devices/register",
        json={
            "public_key_pem": pub_pem,
            "platform": "android",
            "attestation_type": "key_attestation",
            "attestation_statement": "dGVzdF9zdGF0ZW1lbnQ=",
            "attestation_challenge": "invalid_challenge_nonce_0000000000000000000000000000000000000000",
        },
    )
    assert bad_res.status_code == 400
    assert "rejected" in bad_res.json()["detail"].lower()

    # 3. Register device without attestation statement -> accepted as key_registered
    ok_res = await client.post(
        "/api/v1/devices/register",
        json={
            "public_key_pem": pub_pem,
            "platform": "android",
            "device_model": "Pixel 8",
            "os_version": "Android 14",
        },
    )
    assert ok_res.status_code == 201
    assert ok_res.json()["attestation_status"] == "key_registered"


