import uuid
from typing import List, Optional, Dict, Any
from fastapi import APIRouter, Depends, Query, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.auth.rbac import AuthenticatedUser, get_current_user, require_role
from app.db.session import get_db
from app.models.session import Session
from app.models.course import Course
from app.models.user import User
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
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Ingests BLE radio advertisement telemetry records into the high-speed DuckDB Lakehouse.
    Protected endpoint: requires authenticated user.
    """
    # If user is a student, ensure they only ingest telemetry for themselves
    if current_user.role == "student":
        u_stmt = select(User).where(User.firebase_uid == current_user.uid)
        u_res = await db.execute(u_stmt)
        user_record = u_res.scalar_one_or_none()
        if user_record:
            for e in payload.events:
                if e.student_id != str(user_record.id) and e.student_id != user_record.firebase_uid:
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="Students may only submit telemetry events matching their own identity.",
                    )

    raw_events = [e.model_dump() for e in payload.events]
    count = data_engineering_engine.ingest_telemetry_batch(raw_events)
    return {
        "status": "success",
        "ingested_count": count,
        "lakehouse_backend": "DuckDB + Apache Arrow Columnar Engine (Parquet Backed)",
    }


@router.get(
    "/fraud-anomalies",
    summary="Run proxy fraud anomaly detection pipeline",
)
async def get_fraud_anomalies(
    session_id: Optional[str] = Query(None, description="Optional filter by session UUID"),
    current_user: AuthenticatedUser = Depends(require_role(["faculty", "admin"])),
    db: AsyncSession = Depends(get_db),
):
    """
    Statistical Proxy Detection Pipeline:
    Analyzes RSSI variance, biometric pass flags, and distance attenuation to identify
    potential buddy-punching, stationary proxy beacons, and out-of-classroom broadcasts.
    Requires faculty or admin role with course ownership check.
    """
    if current_user.role != "admin" and session_id:
        try:
            sid = uuid.UUID(session_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid session ID format.")
        sess_stmt = select(Session).where(Session.id == sid)
        sess_res = await db.execute(sess_stmt)
        sess = sess_res.scalar_one_or_none()
        if not sess:
            raise HTTPException(status_code=404, detail="Session not found.")
        u_stmt = select(User).where(User.firebase_uid == current_user.uid)
        u_res = await db.execute(u_stmt)
        user_record = u_res.scalar_one_or_none()
        if not user_record or sess.started_by != user_record.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You are not authorized to inspect fraud anomalies for another instructor's session.",
            )

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
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Vectorized data engineering pipeline computing cumulative attendance %,
    safe skip margins, and FA alerts.
    Enforces privacy: students only receive their own metrics.
    """
    if current_user.role == "student":
        u_stmt = select(User).where(User.firebase_uid == current_user.uid)
        u_res = await db.execute(u_stmt)
        user_record = u_res.scalar_one_or_none()
        matrix = data_engineering_engine.compute_compliance_matrix(course_id=course_id)
        filtered = [
            m for m in matrix
            if user_record and (
                m.get("student_id") == str(user_record.id) or
                m.get("student_id") == user_record.firebase_uid or
                (user_record.roll_number and m.get("roll_number") == user_record.roll_number)
            )
        ]
        return {
            "course_id": course_id or "all_courses",
            "student_count": len(filtered),
            "compliance": filtered,
        }

    if current_user.role == "faculty" and course_id:
        try:
            cid = uuid.UUID(course_id)
            c_stmt = select(Course).where(Course.id == cid)
        except ValueError:
            c_stmt = select(Course).where(Course.code == course_id.strip())
        c_res = await db.execute(c_stmt)
        course = c_res.scalar_one_or_none()
        if course:
            u_stmt = select(User).where(User.firebase_uid == current_user.uid)
            u_res = await db.execute(u_stmt)
            user_record = u_res.scalar_one_or_none()
            if user_record and course.faculty_id != user_record.id:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="You are not authorized to inspect compliance records for another instructor's course.",
                )

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
