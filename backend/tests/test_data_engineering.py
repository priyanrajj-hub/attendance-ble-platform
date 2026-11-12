import pytest
import uuid
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.data_engineering.engine import DataEngineeringEngine


@pytest.fixture
def clean_engine():
    engine = DataEngineeringEngine()
    return engine


def test_lakehouse_telemetry_ingestion(clean_engine):
    session_id = str(uuid.uuid4())
    course_id = str(uuid.uuid4())
    student_id = str(uuid.uuid4())

    events = [
        {
            "session_id": session_id,
            "course_id": course_id,
            "student_id": student_id,
            "roll_number": "CB.EN.U4CCE22001",
            "device_id": "00:11:22:33:44:55",
            "rssi_dbm": -68,
            "tx_power": -59,
            "biometric_verified": True,
            "packet_count": 1,
        },
        {
            "session_id": session_id,
            "course_id": course_id,
            "student_id": student_id,
            "roll_number": "CB.EN.U4CCE22001",
            "device_id": "00:11:22:33:44:55",
            "rssi_dbm": -71,
            "tx_power": -59,
            "biometric_verified": True,
            "packet_count": 2,
        },
    ]

    count = clean_engine.ingest_telemetry_batch(events)
    assert count == 2

    # Check compliance calculation
    matrix = clean_engine.compute_compliance_matrix(course_id=course_id)
    assert len(matrix) == 1
    assert matrix[0]["student_id"] == student_id
    assert matrix[0]["attended"] == 1


def test_fraud_detection_stationary_proxy(clean_engine):
    """
    Test that an unnatural flat RSSI stream (standard deviation < 0.25 dBm over 5 packets)
    is caught by the stationary proxy anomaly detector.
    """
    session_id = str(uuid.uuid4())
    student_id = str(uuid.uuid4())

    # 6 packets with identical RSSI (simulated stationary beacon / proxy script)
    events = [
        {
            "session_id": session_id,
            "course_id": "c1",
            "student_id": student_id,
            "roll_number": "CB.EN.U4CCE22099",
            "device_id": "aa:bb:cc:dd:ee:ff",
            "rssi_dbm": -70,
            "biometric_verified": True,
        }
        for _ in range(6)
    ]

    clean_engine.ingest_telemetry_batch(events)
    anomalies = clean_engine.run_proxy_fraud_detection(session_id=session_id)

    assert len(anomalies) >= 1
    anomaly = next(a for a in anomalies if a["student_id"] == student_id)
    assert any("STATIONARY_PROXY_ANOMALY" in f for f in anomaly["fraud_flags"])
    assert anomaly["risk_score"] >= 0.70


def test_fraud_detection_unverified_biometric(clean_engine):
    """
    Test that packets sent without native biometric verification are immediately flagged.
    """
    session_id = str(uuid.uuid4())
    student_id = str(uuid.uuid4())

    events = [
        {
            "session_id": session_id,
            "course_id": "c2",
            "student_id": student_id,
            "roll_number": "CB.EN.U4CCE22055",
            "device_id": "11:22:33:44:55:66",
            "rssi_dbm": -65,
            "biometric_verified": False,  # Bypass attempt!
        },
        {
            "session_id": session_id,
            "course_id": "c2",
            "student_id": student_id,
            "roll_number": "CB.EN.U4CCE22055",
            "device_id": "11:22:33:44:55:66",
            "rssi_dbm": -66,
            "biometric_verified": False,
        },
    ]

    clean_engine.ingest_telemetry_batch(events)
    anomalies = clean_engine.run_proxy_fraud_detection(session_id=session_id)

    assert len(anomalies) >= 1
    anomaly = next(a for a in anomalies if a["student_id"] == student_id)
    assert any("BIOMETRIC_UNVERIFIED" in f for f in anomaly["fraud_flags"])
    assert anomaly["risk_score"] >= 0.90


def test_cryptographic_audit_seal(clean_engine):
    events = [
        {
            "session_id": "s1",
            "course_id": "c1",
            "student_id": "u1",
            "roll_number": "R1",
            "device_id": "d1",
            "rssi_dbm": -65,
            "biometric_verified": True,
        }
    ]
    clean_engine.ingest_telemetry_batch(events)
    seal = clean_engine.generate_cryptographic_audit_seal()

    assert seal["total_records_sealed"] == 1
    assert "merkle_seal_hash" in seal
    assert len(seal["merkle_seal_hash"]) == 64  # SHA-256


from app.auth.rbac import get_current_user, AuthenticatedUser


@pytest.mark.asyncio
async def test_data_pipeline_api_routes(
    client: AsyncClient, mock_faculty_user: AuthenticatedUser, mock_admin_user: AuthenticatedUser
):
    app.dependency_overrides[get_current_user] = lambda: mock_faculty_user

    session_id = str(uuid.uuid4())
    # 1. Ingest telemetry batch
    ingest_res = await client.post(
        "/api/v1/pipeline/telemetry/ingest",
        json={
            "events": [
                {
                    "session_id": session_id,
                    "course_id": "course-101",
                    "student_id": "student-1",
                    "roll_number": "CB.EN.U4CCE22001",
                    "device_id": "00:AA:BB:CC:DD:EE",
                    "rssi_dbm": -68,
                    "biometric_verified": True,
                },
                {
                    "session_id": session_id,
                    "course_id": "course-101",
                    "student_id": "student-1",
                    "roll_number": "CB.EN.U4CCE22001",
                    "device_id": "00:AA:BB:CC:DD:EE",
                    "rssi_dbm": -70,
                    "biometric_verified": True,
                },
            ]
        },
    )
    assert ingest_res.status_code == 201
    assert ingest_res.json()["ingested_count"] == 2

    # 2. Get Compliance Matrix
    comp_res = await client.get("/api/v1/pipeline/compliance-matrix?course_id=course-101")
    assert comp_res.status_code == 200
    data = comp_res.json()
    assert data["student_count"] >= 1

    # 3. Get Cryptographic Audit Seal (admin override)
    app.dependency_overrides[get_current_user] = lambda: mock_admin_user
    seal_res = await client.get("/api/v1/pipeline/audit-seal")
    assert seal_res.status_code == 200
    assert "merkle_seal_hash" in seal_res.json()
