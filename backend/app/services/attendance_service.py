import uuid
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

        # 6. Validate rotating BLE challenge
        is_challenge_valid = await ChallengeService.verify_challenge(
            db, sess, payload.ephemeral_nonce, payload.client_timestamp
        )
        if not is_challenge_valid:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Invalid or expired BLE proximity nonce challenge.",
            )

        # 7. Device & Asymmetric Signature Verification (Mandatory)
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

        # 8. Create attendance record with database transaction idempotency
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
            await db.commit()
            await db.refresh(new_record)
        except IntegrityError:
            await db.rollback()
            # Concurrent race caught by uq_session_student
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
                detail="Attendance registration conflict.",
            )

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
