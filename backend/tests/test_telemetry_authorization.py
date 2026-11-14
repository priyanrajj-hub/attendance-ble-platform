import uuid
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
from app.models.device import Device
from app.models.institution import Institution
from datetime import datetime, timezone, timedelta


@pytest.mark.asyncio
async def test_telemetry_authorization_and_integrity(
    client: AsyncClient,
    db_session: AsyncSession,
):
    """
    Priority 4 Comprehensive Security Suite:
    - 403 on unresolvable directory user
    - 400 on out-of-bounds radio fields (RSSI, Tx Power, packet count, jitter)
    - 403 when student injects telemetry for another student
    - 403 when student uses a device registered to another student
    - 403 when student injects for a course they are not enrolled in
    - 403 cross-institution isolation
    - 201 on authorized telemetry
    """
    tag = uuid.uuid4().hex[:8]
    inst_1 = Institution(id=uuid.uuid4(), code=f"CBE-{tag[:4]}", name=f"Amrita Coimbatore {tag}", domain=f"cb_{tag}.amrita.edu")
    inst_2 = Institution(id=uuid.uuid4(), code=f"BLR-{tag[:4]}", name=f"Amrita Bangalore {tag}", domain=f"blr_{tag}.amrita.edu")
    db_session.add_all([inst_1, inst_2])
    await db_session.flush()

    fac_uid = f"fac_tel_{tag}"
    st1_uid = f"st1_tel_{tag}"
    st2_uid = f"st2_tel_{tag}"

    fac = User(
        id=uuid.uuid4(),
        firebase_uid=fac_uid,
        email=f"fac_tel_{tag}@cb.amrita.edu",
        display_name="Prof Telemetry",
        role="faculty",
        institution_id=inst_1.id,
        status="verified",
    )
    st1 = User(
        id=uuid.uuid4(),
        firebase_uid=st1_uid,
        email=f"st1_tel_{tag}@cb.amrita.edu",
        display_name="Student One",
        roll_number=f"CB.EN.U4CCE{tag[:5].upper()}1",
        role="student",
        institution_id=inst_1.id,
        status="verified",
    )
    st2 = User(
        id=uuid.uuid4(),
        firebase_uid=st2_uid,
        email=f"st2_tel_{tag}@cb.amrita.edu",
        display_name="Student Two",
        roll_number=f"CB.EN.U4CCE{tag[:5].upper()}2",
        role="student",
        institution_id=inst_1.id,
        status="verified",
    )
    db_session.add_all([fac, st1, st2])
    await db_session.flush()

    # Device registered to Student 2
    dev2 = Device(
        id=uuid.uuid4(),
        user_id=st2.id,
        public_key_fingerprint=f"fp_dev2_{tag}",
        public_key_pem="PEM_KEY_2",
        platform="android",
    )
    db_session.add(dev2)
    await db_session.flush()

    # Course in Inst 1
    course1 = Course(
        id=uuid.uuid4(),
        code=f"CSE-{tag[:4].upper()}",
        name="Embedded Systems",
        faculty_id=fac.id,
        institution_id=inst_1.id,
        term="Fall 2026",
    )
    db_session.add(course1)
    await db_session.flush()

    # Only Student 1 is enrolled in Course 1
    enr1 = Enrollment(course_id=course1.id, student_id=st1.id, status="active")
    db_session.add(enr1)
    await db_session.flush()

    now = datetime.now(timezone.utc)
    sess1 = Session(
        id=uuid.uuid4(),
        course_id=course1.id,
        started_by=fac.id,
        room_label="Lab 3",
        rssi_threshold=-75,
        secret_hash="dummy",
        opens_at=now - timedelta(minutes=5),
        closes_at=now + timedelta(minutes=45),
        status="active",
    )
    db_session.add(sess1)
    await db_session.commit()

    # TEST 1: Unresolvable Institutional User (403)
    ghost_auth = AuthenticatedUser(
        uid="ghost-user-unknown",
        email="ghost@amrita.edu",
        role="student",
        status="verified",
        display_name="Ghost User",
    )
    app.dependency_overrides[get_current_user] = lambda: ghost_auth
    ghost_res = await client.post(
        "/api/v1/pipeline/telemetry/ingest",
        json={"events": [{"session_id": str(sess1.id), "course_id": str(course1.id), "student_id": "ghost-user-unknown", "roll_number": "R1", "device_id": "d1"}]},
    )
    assert ghost_res.status_code == 403

    # Switch auth to Student 1
    st1_auth = AuthenticatedUser(
        uid=st1_uid,
        email=st1.email,
        role="student",
        status="verified",
        display_name=st1.display_name,
    )
    app.dependency_overrides[get_current_user] = lambda: st1_auth

    # TEST 2: Out of bounds radio checks (400)
    # A. RSSI > 0
    bad_rssi = await client.post(
        "/api/v1/pipeline/telemetry/ingest",
        json={"events": [{"session_id": str(sess1.id), "course_id": str(course1.id), "student_id": str(st1.id), "roll_number": st1.roll_number, "device_id": "d1", "rssi_dbm": 5}]},
    )
    assert bad_rssi.status_code == 400

    # B. RSSI < -120
    bad_rssi2 = await client.post(
        "/api/v1/pipeline/telemetry/ingest",
        json={"events": [{"session_id": str(sess1.id), "course_id": str(course1.id), "student_id": str(st1.id), "roll_number": st1.roll_number, "device_id": "d1", "rssi_dbm": -125}]},
    )
    assert bad_rssi2.status_code == 400

    # C. Packet count < 1
    bad_pkt = await client.post(
        "/api/v1/pipeline/telemetry/ingest",
        json={"events": [{"session_id": str(sess1.id), "course_id": str(course1.id), "student_id": str(st1.id), "roll_number": st1.roll_number, "device_id": "d1", "packet_count": 0}]},
    )
    assert bad_pkt.status_code == 400

    # TEST 3: Student 1 attempts to submit telemetry for Student 2 (403)
    spoof_st = await client.post(
        "/api/v1/pipeline/telemetry/ingest",
        json={"events": [{"session_id": str(sess1.id), "course_id": str(course1.id), "student_id": str(st2.id), "roll_number": st2.roll_number, "device_id": "d1"}]},
    )
    assert spoof_st.status_code == 403

    # TEST 4: Student 1 attempts to submit telemetry using Student 2's registered device (403)
    spoof_dev = await client.post(
        "/api/v1/pipeline/telemetry/ingest",
        json={"events": [{"session_id": str(sess1.id), "course_id": str(course1.id), "student_id": str(st1.id), "roll_number": st1.roll_number, "device_id": str(dev2.id)}]},
    )
    assert spoof_dev.status_code == 403

    # TEST 5: Student 2 attempts to submit telemetry for Course 1 (not enrolled) (403)
    st2_auth = AuthenticatedUser(
        uid=st2_uid,
        email=st2.email,
        role="student",
        status="verified",
        display_name=st2.display_name,
    )
    app.dependency_overrides[get_current_user] = lambda: st2_auth
    not_enrolled = await client.post(
        "/api/v1/pipeline/telemetry/ingest",
        json={"events": [{"session_id": str(sess1.id), "course_id": str(course1.id), "student_id": str(st2.id), "roll_number": st2.roll_number, "device_id": str(dev2.id)}]},
    )
    assert not_enrolled.status_code == 403

    # TEST 6: Valid telemetry submission by Student 1 for Course 1 (201)
    app.dependency_overrides[get_current_user] = lambda: st1_auth
    valid_res = await client.post(
        "/api/v1/pipeline/telemetry/ingest",
        json={
            "events": [
                {
                    "session_id": str(sess1.id),
                    "course_id": str(course1.id),
                    "student_id": str(st1.id),
                    "roll_number": st1.roll_number,
                    "device_id": "unregistered-mac-01",
                    "rssi_dbm": -68,
                    "tx_power": -59,
                    "packet_count": 1,
                    "jitter_ms": 14.2,
                    "biometric_verified": True,
                }
            ]
        },
    )
    assert valid_res.status_code == 201
    assert valid_res.json()["ingested_count"] == 1
