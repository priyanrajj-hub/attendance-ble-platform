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
        Validates 128-bit session-bound HMAC-SHA256 challenges across the active tolerance window.
        Enforces client timestamp freshness against server clock drift.
        """
        if not submitted_nonce or not submitted_nonce.strip():
            return False

        now = datetime.now(timezone.utc)
        clean_nonce = submitted_nonce.strip().lower()

        # Enforce client timestamp freshness (within 60 seconds) if provided
        if client_timestamp is not None:
            now_ms = int(now.timestamp() * 1000)
            if abs(now_ms - client_timestamp) > 60_000:
                return False

        # Check against 128-bit session-bound rotating challenges
        valid_128 = cls.get_valid_challenges(session.secret_hash, str(session.id), now)
        if clean_nonce in [c.lower() for c in valid_128]:
            return True

        return False
