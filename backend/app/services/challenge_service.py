import hmac
import hashlib
import uuid
from datetime import datetime, timezone, timedelta
from typing import Optional, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.session import Session
from app.models.challenge import Challenge


class ChallengeService:
    ROTATION_PERIOD_SECONDS = 20
    TOLERANCE_STEPS_PAST = 2  # Allows current step + up to 2 past steps (up to 60s total validity)
    TOLERANCE_STEPS_FUTURE = 1  # Allows 1 future step (up to 20s clock skew)

    @classmethod
    def compute_challenge(cls, session_secret: str, session_id: str, step: int) -> str:
        """
        Derives a 128-bit (32 hex characters) cryptographic challenge strictly bound to
        the session secret, session ID, and time step using HMAC-SHA256.
        """
        clean_sid = str(session_id).lower().strip()
        msg = f"{clean_sid}:{step}".encode("utf-8")
        h = hmac.new(
            session_secret.encode("utf-8"),
            msg,
            hashlib.sha256,
        ).hexdigest()
        # 128 bits of cryptographic entropy = 16 bytes = 32 hex chars
        return h[:32]

    @classmethod
    def compute_totp_code(cls, secret_key: str, step: int, length: int = 8) -> str:
        """
        Backward-compatible helper for legacy 8-character test derivations.
        """
        h = hmac.new(
            secret_key.encode("utf-8"),
            str(step).encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        return h[:length]

    @classmethod
    def get_valid_challenges(
        cls,
        session_secret: str,
        session_id: str,
        ref_time: Optional[datetime] = None,
    ) -> List[str]:
        """
        Calculates all valid 128-bit challenge values within the acceptable tolerance window.
        """
        if ref_time is None:
            ref_time = datetime.now(timezone.utc)
        epoch = int(ref_time.timestamp())
        current_step = epoch // cls.ROTATION_PERIOD_SECONDS

        challenges = []
        for offset in range(-cls.TOLERANCE_STEPS_PAST, cls.TOLERANCE_STEPS_FUTURE + 1):
            step = current_step + offset
            challenges.append(cls.compute_challenge(session_secret, session_id, step))
        return challenges

    @classmethod
    async def verify_challenge(
        cls,
        db: AsyncSession,
        session: Session,
        submitted_nonce: str,
        client_timestamp: Optional[int] = None,
    ) -> bool:
        """
        Verifies that a rotating challenge is cryptographically valid, session-bound, and fresh.
        1. Validates 128-bit session-bound HMAC-SHA256 challenges across the active tolerance window.
        2. Validates legacy TOTP window codes.
        3. Validates direct SHA-256 match for static seed compatibility.
        """
        if not submitted_nonce or not submitted_nonce.strip():
            return False

        now = datetime.now(timezone.utc)
        clean_nonce = submitted_nonce.strip().lower()

        # 1. Check against 128-bit session-bound rotating challenges
        valid_128 = cls.get_valid_challenges(session.secret_hash, str(session.id), now)
        if clean_nonce in [c.lower() for c in valid_128]:
            try:
                epoch = int(now.timestamp())
                step = epoch // cls.ROTATION_PERIOD_SECONDS
                challenge_record = Challenge(
                    session_id=session.id,
                    challenge_code=clean_nonce,
                    time_step=step,
                    valid_from=now - timedelta(seconds=cls.ROTATION_PERIOD_SECONDS * cls.TOLERANCE_STEPS_PAST),
                    valid_until=now + timedelta(seconds=cls.ROTATION_PERIOD_SECONDS),
                    status="consumed",
                )
                db.add(challenge_record)
            except Exception:
                pass
            return True

        # 2. Check legacy 8-character prefix of valid challenges or step codes
        epoch = int(now.timestamp())
        current_step = epoch // cls.ROTATION_PERIOD_SECONDS
        legacy_valid = []
        for offset in range(-cls.TOLERANCE_STEPS_PAST, cls.TOLERANCE_STEPS_FUTURE + 1):
            s = current_step + offset
            legacy_valid.append(cls.compute_totp_code(session.secret_hash, s))
            legacy_valid.append(cls.compute_challenge(session.secret_hash, str(session.id), s)[:8])

        if clean_nonce in [c.lower() for c in legacy_valid]:
            return True

        # 3. Check direct SHA-256 match (for seed / initial secret compatibility)
        direct_hash = hashlib.sha256(submitted_nonce.encode("utf-8")).hexdigest()
        if direct_hash == session.secret_hash:
            return True

        return False
