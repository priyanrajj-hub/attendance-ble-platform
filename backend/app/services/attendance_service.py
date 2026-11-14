import uuid
import hashlib
from datetime import datetime, timezone
from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.auth.rbac import AuthenticatedUser
from app.models.session import Session
from app.models.user import User
from app.models.enrollment import Enrollment
from app.models.attendance_record import AttendanceRecord
from app.models.audit_log import AuditLog
from app.schemas.checkin import CheckInPayload, CheckInResponse
from app.services.challenge_service import ChallengeService
from app.services.device_verification_service import DeviceVerificationService
from app.services.replay_protection_service import ReplayProtectionService


class AttendanceService:
    @classmethod
    async def process_proximity_checkin(
        cls,
        payload: CheckInPayload,
        current_user: AuthenticatedUser,
        db: AsyncSession,
    ) -> CheckInResponse:
        # 1. Parse and validate session ID
        try:
            sid = uuid.UUID(payload.session_id)
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid session ID format.",
            )

        # 2. Fetch session
        sess_stmt = select(Session).where(Session.id == sid)
        sess_res = await db.execute(sess_stmt)
        sess = sess_res.scalar_one_or_none()
        if not sess:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Session not found.",
            )

        now = datetime.now(timezone.utc)
        if sess.status != "active":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Session is {sess.status}, not open for attendance.",
            )
        if now >= sess.closes_at:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Session attendance window has expired.",
            )

        # 3. Fetch student user record
        u_stmt = select(User).where(User.firebase_uid == current_user.uid)
        u_res = await db.execute(u_stmt)
        user_record = u_res.scalar_one_or_none()
        if not user_record:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Student profile not found.",
            )
        if user_record.status != "verified":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Account status '{user_record.status}' is not verified for attendance.",
            )

        # 4. Verify enrollment
        enr_stmt = select(Enrollment).where(
            Enrollment.course_id == sess.course_id,
            Enrollment.student_id == user_record.id,
            Enrollment.status == "active",
        )
        enr_res = await db.execute(enr_stmt)
        enrolled = enr_res.scalar_one_or_none()
        if not enrolled:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Student is not enrolled in this course.",
            )

        # 5. Check idempotency (already marked)
        existing_record = await ReplayProtectionService.get_existing_attendance(
            db, sid, user_record.id
        )
        if existing_record:
            return CheckInResponse(
                attendance_id=str(existing_record.id),
                session_id=str(existing_record.session_id),
                student_id=str(existing_record.student_id),
                status=existing_record.status,
                method=existing_record.method,
                verified_at=existing_record.verified_at,
                already_marked=True,
                signature_verified=existing_record.signature_verified,
                message="Attendance already recorded for this session.",
            )

        # 6. Validate observed RSSI proximity against session threshold
        if payload.observed_rssi > 0 or payload.observed_rssi < -120:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Observed RSSI value {payload.observed_rssi} dBm is invalid (must be between -120 and 0 dBm).",
            )
        if payload.observed_rssi < sess.rssi_threshold:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Observed RSSI ({payload.observed_rssi} dBm) does not meet session proximity threshold ({sess.rssi_threshold} dBm).",
            )

        # 7. Validate client timestamp freshness
        if payload.client_timestamp is not None:
            now_ms = int(now.timestamp() * 1000)
            if payload.client_timestamp > now_ms + 10_000:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Client timestamp is in the future. Clock synchronization error.",
                )
            if payload.client_timestamp < now_ms - 60_000:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Client timestamp is stale (older than 60 seconds).",
                )

        # 8. Validate rotating BLE challenge
        is_challenge_valid = await ChallengeService.verify_challenge(
            db, sess, payload.ephemeral_nonce, payload.client_timestamp
        )
        if not is_challenge_valid:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Invalid or expired BLE proximity nonce challenge.",
            )

        # 9. Device & Asymmetric Signature Verification (Mandatory)
        if not payload.signature or not payload.signature.strip():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cryptographic device signature is required for proximity attendance.",
            )

        sig_ok, device = await DeviceVerificationService.verify_device_and_signature(
            db,
            user_record,
            payload.session_id,
            payload.ephemeral_nonce,
            payload.client_timestamp,
            payload.signature,
            payload.public_key_fingerprint,
        )
        if not sig_ok:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Cryptographic device signature verification failed.",
            )
        signature_verified = True
        device_id = device.id if device else None

        # 10. Replay Protection: Check if this signature or nonce was already consumed
        is_replayed, replay_reason = await ReplayProtectionService.check_replay(
            db, sid, user_record.id, payload.ephemeral_nonce, payload.signature
        )
        if is_replayed:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=replay_reason,
            )

        # 11. Create attendance record with database transaction idempotency and audit trail
        new_record = AttendanceRecord(
            session_id=sid,
            student_id=user_record.id,
            device_id=device_id,
            method="ble_signed_nonce",
            rssi_observed=payload.observed_rssi,
            signature_verified=signature_verified,
            verified_at=now,
            status="present",
        )

        try:
            async with db.begin_nested():
                db.add(new_record)
                await db.flush()

                # Record consumed nonce and signature hash for strict replay protection
                await ReplayProtectionService.record_consumption(
                    db, sid, user_record.id, payload.ephemeral_nonce, payload.signature
                )

                # Persist immutable audit log entry in PostgreSQL
                audit_entry = AuditLog(
                    actor_id=user_record.id,
                    action="proximity_checkin",
                    target_entity="attendance_records",
                    target_id=str(new_record.id),
                    ip_hash=hashlib.sha256(user_record.firebase_uid.encode("utf-8")).hexdigest()[:64],
                    request_id=uuid.uuid4().hex,
                    payload={
                        "session_id": str(sid),
                        "method": "ble_signed_nonce",
                        "rssi_observed": payload.observed_rssi,
                        "device_id": str(device_id) if device_id else None,
                        "timestamp_ms": payload.client_timestamp,
                    },
                    created_at=now,
                )
                db.add(audit_entry)
                await db.flush()

            await db.commit()
            await db.refresh(new_record)
        except IntegrityError:
            await db.rollback()
            # Concurrent race caught by uq_session_student or consumed nonce
            race_record = await ReplayProtectionService.get_existing_attendance(
                db, sid, user_record.id
            )
            if race_record:
                return CheckInResponse(
                    attendance_id=str(race_record.id),
                    session_id=str(race_record.session_id),
                    student_id=str(race_record.student_id),
                    status=race_record.status,
                    method=race_record.method,
                    verified_at=race_record.verified_at,
                    already_marked=True,
                    signature_verified=race_record.signature_verified,
                    message="Attendance already recorded for this session.",
                )
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Attendance registration conflict or replay detected.",
            )

        # 9. Asynchronously project verified attendance into Firestore for live UI synchronization
        try:
            from firebase_admin import firestore
            fs = firestore.client()
            fs.collection("sessions").document(str(sid)).collection("attendance").document(user_record.firebase_uid).set({
                "studentUid": user_record.firebase_uid,
                "studentName": user_record.display_name or user_record.roll_number or "Student",
                "rollNo": user_record.roll_number or "",
                "markedAt": now,
                "method": new_record.method,
                "rssi": payload.observed_rssi,
                "status": "present",
            })
        except Exception:
            pass  # PostgreSQL is the sole authoritative attendance ledger

        return CheckInResponse(
            attendance_id=str(new_record.id),
            session_id=str(new_record.session_id),
            student_id=str(new_record.student_id),
            status=new_record.status,
            method=new_record.method,
            verified_at=new_record.verified_at,
            already_marked=False,
            signature_verified=new_record.signature_verified,
            message="Attendance verified and recorded successfully.",
        )
