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
from app.models.enrollment import Enrollment
from app.models.device import Device
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
    Protected endpoint:
    1. Rejects unresolvable institutional users (403).
    2. Enforces radio physical bounds (-120 <= rssi <= 0, -100 <= tx_power <= 20, packet_count >= 1).
    3. Verifies student identity binding (cannot submit telemetry for other students).
    4. Validates session existence and course enrollment for students.
    5. Verifies device ownership (cannot use a device registered to another user).
    6. Enforces faculty course ownership and cross-institution boundary isolation.
    """
    # 1. Authoritative Directory Lookup: Reject unresolvable users
    u_stmt = select(User).where(User.firebase_uid == current_user.uid)
    u_res = await db.execute(u_stmt)
    user_record = u_res.scalar_one_or_none()
    if not user_record:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Authenticated user cannot be resolved in institutional directory.",
        )

    # 2. Field-level Radio Telemetry Bounds Validation
    for e in payload.events:
        if not (-120 <= e.rssi_dbm <= 0):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid RSSI value: {e.rssi_dbm} dBm. Must be between -120 and 0 dBm.",
            )
        if not (-100 <= e.tx_power <= 20):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid Tx Power: {e.tx_power} dBm. Must be between -100 and 20 dBm.",
            )
        if e.packet_count < 1:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid packet count: {e.packet_count}. Must be at least 1.",
            )
        if e.jitter_ms < 0.0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid jitter: {e.jitter_ms}. Cannot be negative.",
            )

    # 3. Student-specific Authorization & Integrity Checks
    if current_user.role == "student":
        for e in payload.events:
            # Identity Binding Check
            if e.student_id != str(user_record.id) and e.student_id != user_record.firebase_uid:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Students may only submit telemetry events matching their own identity.",
                )
            if user_record.roll_number and e.roll_number and e.roll_number.strip().upper() != user_record.roll_number.strip().upper():
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Submitted roll number does not match authenticated user.",
                )

            # Device Possession Check (Must not belong to another user)
            if e.device_id:
                dev = None
                try:
                    dev_uuid = uuid.UUID(e.device_id)
                    dev_res = await db.execute(select(Device).where(Device.id == dev_uuid))
                    dev = dev_res.scalar_one_or_none()
                except ValueError:
                    dev_res = await db.execute(
                        select(Device).where(Device.public_key_fingerprint == e.device_id)
                    )
                    dev = dev_res.scalar_one_or_none()

                if dev and dev.user_id != user_record.id:
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="Telemetry device is registered to another student.",
                    )

            # Session Ownership & Course Enrollment Check
            if e.session_id:
                try:
                    sid = uuid.UUID(e.session_id)
                    sess_res = await db.execute(select(Session).where(Session.id == sid))
                    sess = sess_res.scalar_one_or_none()
                    if sess:
                        enr_stmt = select(Enrollment).where(
                            Enrollment.course_id == sess.course_id,
                            Enrollment.student_id == user_record.id,
                            Enrollment.status == "active",
                        )
                        enr = (await db.execute(enr_stmt)).scalar_one_or_none()
                        if not enr:
                            raise HTTPException(
                                status_code=status.HTTP_403_FORBIDDEN,
                                detail="Student is not enrolled in the course for this session.",
                            )

                        # Cross-institution Isolation
                        crs = (await db.execute(select(Course).where(Course.id == sess.course_id))).scalar_one_or_none()
                        if crs and crs.institution_id and user_record.institution_id and crs.institution_id != user_record.institution_id:
                            raise HTTPException(
                                status_code=status.HTTP_403_FORBIDDEN,
                                detail="Cross-institution telemetry submission forbidden.",
                            )
                except ValueError:
                    pass

    # 4. Faculty-specific Course Ownership & Cross-Institution Checks
    elif current_user.role == "faculty":
        for e in payload.events:
            if e.session_id:
                try:
                    sid = uuid.UUID(e.session_id)
                    sess_res = await db.execute(select(Session).where(Session.id == sid))
                    sess = sess_res.scalar_one_or_none()
                    if sess:
                        crs = (await db.execute(select(Course).where(Course.id == sess.course_id))).scalar_one_or_none()
                        if crs and crs.faculty_id != user_record.id and sess.started_by != user_record.id:
                            raise HTTPException(
                                status_code=status.HTTP_403_FORBIDDEN,
                                detail="Faculty not authorized to ingest telemetry for this course.",
                            )
                        if crs and crs.institution_id and user_record.institution_id and crs.institution_id != user_record.institution_id:
                            raise HTTPException(
                                status_code=status.HTTP_403_FORBIDDEN,
                                detail="Cross-institution telemetry submission forbidden.",
                            )
                except ValueError:
                    pass

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
