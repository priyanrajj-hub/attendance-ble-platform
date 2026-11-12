from typing import List, Optional, Dict, Any
from fastapi import APIRouter, Depends, Query, status
from pydantic import BaseModel
from app.auth.rbac import get_current_user, require_role
from app.data_engineering.engine import data_engineering_engine

router = APIRouter(prefix="/pipeline", tags=["Data Engineering & Telemetry"])


class TelemetryEventSchema(BaseModel):
    event_id: Optional[str] = None
    session_id: str
    course_id: str
    student_id: str
    roll_number: str
    device_id: str
    rssi_dbm: int = -70
    tx_power: int = -59
    biometric_verified: bool = True
    signature_hash: Optional[str] = None
    packet_count: int = 1
    jitter_ms: float = 12.0


class TelemetryBatchRequest(BaseModel):
    events: List[TelemetryEventSchema]


@router.post(
    "/telemetry/ingest",
    status_code=status.HTTP_201_CREATED,
    summary="Ingest batch BLE telemetry into columnar lakehouse",
)
async def ingest_telemetry_batch(
    payload: TelemetryBatchRequest,
    current_user: dict = Depends(get_current_user),
):
    """
    Ingests BLE radio advertisement telemetry records into the high-speed DuckDB Lakehouse.
    Protected endpoint: requires authenticated faculty or student.
    """
    raw_events = [e.model_dump() for e in payload.events]
    count = data_engineering_engine.ingest_telemetry_batch(raw_events)
    return {
        "status": "success",
        "ingested_count": count,
        "lakehouse_backend": "DuckDB + Apache Arrow Columnar Engine",
    }


@router.get(
    "/fraud-anomalies",
    summary="Run proxy fraud anomaly detection pipeline",
)
async def get_fraud_anomalies(
    session_id: Optional[str] = Query(None, description="Optional filter by session UUID"),
    current_user: dict = Depends(require_role(["faculty", "admin"])),
):
    """
    Statistical Proxy Detection Pipeline:
    Analyzes RSSI variance, biometric pass flags, and distance attenuation to identify
    potential buddy-punching, stationary proxy beacons, and out-of-classroom broadcasts.
    Requires faculty or admin role.
    """
    anomalies = data_engineering_engine.run_proxy_fraud_detection(session_id=session_id)
    return {
        "session_id": session_id or "all_sessions",
        "anomalies_detected": len(anomalies),
        "results": anomalies,
    }


@router.get(
    "/compliance-matrix",
    summary="Compute 75% attendance compliance matrix",
)
async def get_compliance_matrix(
    course_id: Optional[str] = Query(None, description="Optional filter by course UUID"),
    current_user: dict = Depends(get_current_user),
):
    """
    Vectorized data engineering pipeline computing cumulative attendance %,
    safe skip margins, and FA alerts for all students.
    """
    matrix = data_engineering_engine.compute_compliance_matrix(course_id=course_id)
    return {
        "course_id": course_id or "all_courses",
        "student_count": len(matrix),
        "compliance": matrix,
    }


@router.get(
    "/audit-seal",
    summary="Generate tamper-proof cryptographic audit seal",
)
async def get_audit_seal(
    current_user: dict = Depends(require_role(["admin", "faculty"])),
):
    """
    Produces a SHA-256 Merkle-style cryptographic seal across all ingested telemetry,
    preventing tampering with historical attendance data.
    """
    seal = data_engineering_engine.generate_cryptographic_audit_seal()
    return seal
