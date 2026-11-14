import uuid
import hashlib
from typing import Optional, Tuple
from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.attendance_record import AttendanceRecord
from app.models.consumed_nonce import ConsumedNonce


class ReplayProtectionService:
    @classmethod
    async def get_existing_attendance(
        cls,
        db: AsyncSession,
        session_id: uuid.UUID,
        student_id: uuid.UUID,
    ) -> Optional[AttendanceRecord]:
        """
        Retrieves existing attendance record for a student in a session.
        """
        stmt = select(AttendanceRecord).where(
            AttendanceRecord.session_id == session_id,
            AttendanceRecord.student_id == student_id,
        )
        res = await db.execute(stmt)
        return res.scalar_one_or_none()

    @classmethod
    def compute_signature_hash(cls, signature: str) -> str:
        return hashlib.sha256(signature.strip().encode("utf-8")).hexdigest()

    @classmethod
    async def check_replay(
        cls,
        db: AsyncSession,
        session_id: uuid.UUID,
        student_id: uuid.UUID,
        nonce: str,
        signature: str,
    ) -> Tuple[bool, str]:
        """
        Verifies if this specific signature or (session, student, nonce) tuple has already been submitted.
        Returns (is_replayed, reason).
        """
        clean_nonce = nonce.strip().lower()
        sig_hash = cls.compute_signature_hash(signature)

        # 1. Check if signature was already used across the session
        stmt_sig = select(ConsumedNonce).where(
            ConsumedNonce.session_id == session_id,
            ConsumedNonce.signature_hash == sig_hash,
        )
        res_sig = await db.execute(stmt_sig)
        if res_sig.scalar_one_or_none():
            return True, "Cryptographic signature replay detected: this signature has already been consumed."

        # 2. Check if student already used this challenge nonce in this session
        stmt_nonce = select(ConsumedNonce).where(
            ConsumedNonce.session_id == session_id,
            ConsumedNonce.student_id == student_id,
            ConsumedNonce.nonce == clean_nonce,
        )
        res_nonce = await db.execute(stmt_nonce)
        if res_nonce.scalar_one_or_none():
            return True, "Challenge nonce replay detected: student has already consumed this challenge."

        return False, ""

    @classmethod
    async def record_consumption(
        cls,
        db: AsyncSession,
        session_id: uuid.UUID,
        student_id: uuid.UUID,
        nonce: str,
        signature: str,
    ) -> ConsumedNonce:
        """
        Persists consumed nonce and signature hash inside the active transaction.
        """
        clean_nonce = nonce.strip().lower()
        sig_hash = cls.compute_signature_hash(signature)
        consumed = ConsumedNonce(
            session_id=session_id,
            student_id=student_id,
            nonce=clean_nonce,
            signature_hash=sig_hash,
            consumed_at=datetime.now(timezone.utc),
        )
        db.add(consumed)
        return consumed
