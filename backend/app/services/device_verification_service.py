import uuid
import hashlib
import hmac
import base64
from typing import Optional, Tuple
from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import ec, rsa, ed25519, padding

from app.models.device import Device
from app.models.user import User


class DeviceVerificationService:
    @staticmethod
    def compute_fingerprint(public_key_pem: str) -> str:
        """
        Derives the SHA-256 fingerprint from the SubjectPublicKeyInfo DER encoding of the PEM public key
        or from the raw key string.
        """
        clean_key = public_key_pem.strip()
        if clean_key.startswith("-----BEGIN"):
            pub_key = serialization.load_pem_public_key(clean_key.encode("utf-8"))
            der_bytes = pub_key.public_bytes(
                encoding=serialization.Encoding.DER,
                format=serialization.PublicFormat.SubjectPublicKeyInfo,
            )
            return hashlib.sha256(der_bytes).hexdigest()
        else:
            return hashlib.sha256(clean_key.encode("utf-8")).hexdigest()

    @staticmethod
    def verify_signature(public_key_pem: str, message: bytes, signature_str: str) -> bool:
        """
        Verifies a cryptographic signature over message bytes using the provided public key.
        Supports ECDSA (SHA-256), RSA (PKCS1v15 / PSS), Ed25519, and Keystore HMAC-SHA256.
        Signature can be provided in Hex or Base64 format.
        """
        if not signature_str:
            return False

        clean_key = public_key_pem.strip()

        # 1. Symmetric Keystore Key (HMAC-SHA256)
        if clean_key.startswith("HMAC-SHA256:"):
            secret = clean_key.split("HMAC-SHA256:", 1)[1].strip()
            expected_hex = hmac.new(secret.encode("utf-8"), message, hashlib.sha256).hexdigest()
            sig_clean = signature_str.strip().lower()
            return hmac.compare_digest(expected_hex, sig_clean)

        # 2. Asymmetric Public Key (ECDSA / RSA / Ed25519)
        try:
            try:
                sig_bytes = bytes.fromhex(signature_str.strip())
            except ValueError:
                sig_bytes = base64.b64decode(signature_str.strip())

            pub_key = serialization.load_pem_public_key(clean_key.encode("utf-8"))

            if isinstance(pub_key, ec.EllipticCurvePublicKey):
                pub_key.verify(sig_bytes, message, ec.ECDSA(hashes.SHA256()))
                return True
            elif isinstance(pub_key, rsa.RSAPublicKey):
                try:
                    pub_key.verify(sig_bytes, message, padding.PKCS1v15(), hashes.SHA256())
                    return True
                except Exception:
                    pub_key.verify(
                        sig_bytes,
                        message,
                        padding.PSS(
                            mgf=padding.MGF1(hashes.SHA256()),
                            salt_length=padding.PSS.MAX_LENGTH,
                        ),
                        hashes.SHA256(),
                    )
                    return True
            elif isinstance(pub_key, ed25519.Ed25519PublicKey):
                pub_key.verify(sig_bytes, message)
                return True
        except Exception:
            return False

        return False

    @classmethod
    async def get_active_device(
        cls,
        db: AsyncSession,
        user_id: uuid.UUID,
        fingerprint: Optional[str] = None,
    ) -> Optional[Device]:
        """
        Retrieves the user's active, non-revoked device.
        If a fingerprint is provided, matches that specific device.
        """
        query = select(Device).where(
            Device.user_id == user_id,
            Device.revoked_at.is_(None),
        )
        if fingerprint:
            query = query.where(Device.public_key_fingerprint == fingerprint)

        res = await db.execute(query)
        return res.scalars().first()

    @classmethod
    async def verify_device_and_signature(
        cls,
        db: AsyncSession,
        user: User,
        session_id: str,
        ephemeral_nonce: str,
        client_timestamp: Optional[int],
        signature: Optional[str],
        public_key_fingerprint: Optional[str],
    ) -> Tuple[bool, Optional[Device]]:
        """
        Validates whether the student has an active registered device and verifies the signature.
        Constructs the canonical signed message: '{session_id}:{ephemeral_nonce}:{client_timestamp or ""}'.
        """
        device = await cls.get_active_device(db, user.id, public_key_fingerprint)
        if not device:
            return False, None

        if not signature:
            return False, device

        canonical_message = f"{session_id}:{ephemeral_nonce}:{client_timestamp or ''}".encode("utf-8")
        is_valid = cls.verify_signature(device.public_key_pem, canonical_message, signature)
        return is_valid, device
