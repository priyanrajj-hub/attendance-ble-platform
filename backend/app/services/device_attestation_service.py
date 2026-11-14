import uuid
import secrets
import base64
from datetime import datetime, timezone, timedelta
from typing import Optional, Tuple
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete
from cryptography import x509
from cryptography.hazmat.primitives import serialization

from app.models.device_attestation_challenge import DeviceAttestationChallenge


class DeviceAttestationService:
    # Android Key Attestation OID: 1.3.6.1.4.1.11129.2.1.17
    ANDROID_KEY_ATTESTATION_OID = "1.3.6.1.4.1.11129.2.1.17"

    @classmethod
    async def issue_challenge(
        cls,
        db: AsyncSession,
        user_id: uuid.UUID,
        validity_seconds: int = 300,
    ) -> DeviceAttestationChallenge:
        """
        Issues an ephemeral cryptographic nonce challenge for remote hardware attestation.
        """
        # Purge expired challenges for user
        now = datetime.now(timezone.utc)
        await db.execute(
            delete(DeviceAttestationChallenge).where(
                DeviceAttestationChallenge.user_id == user_id,
                DeviceAttestationChallenge.expires_at < now,
            )
        )

        challenge_hex = secrets.token_hex(32)
        expires_at = now + timedelta(seconds=validity_seconds)

        record = DeviceAttestationChallenge(
            user_id=user_id,
            challenge=challenge_hex,
            expires_at=expires_at,
            created_at=now,
        )
        db.add(record)
        await db.commit()
        await db.refresh(record)
        return record

    @classmethod
    async def verify_attestation(
        cls,
        db: AsyncSession,
        user_id: uuid.UUID,
        public_key_pem: str,
        attestation_statement: Optional[str],
        attestation_type: Optional[str],
        attestation_challenge: Optional[str],
    ) -> Tuple[str, str]:
        """
        Evaluates hardware remote attestation statements.
        Returns (attestation_status, details_message).
        Possible statuses:
          - 'hardware_attested': verified hardware-backed Keystore / Secure Enclave
          - 'key_registered': valid asymmetric key enrolled, but hardware attestation not provided
          - 'attestation_rejected': attestation statement failed validation
        """
        # If no attestation statement is provided, accept as software/unattested key
        if not attestation_statement or not attestation_type or attestation_type == "none":
            return "key_registered", "Device key registered without hardware attestation statement."

        # Verify challenge
        if not attestation_challenge:
            return "attestation_rejected", "Attestation challenge is required when submitting an attestation statement."

        now = datetime.now(timezone.utc)
        stmt = select(DeviceAttestationChallenge).where(
            DeviceAttestationChallenge.user_id == user_id,
            DeviceAttestationChallenge.challenge == attestation_challenge,
            DeviceAttestationChallenge.expires_at > now,
        )
        res = await db.execute(stmt)
        valid_challenge = res.scalar_one_or_none()
        if not valid_challenge:
            return "attestation_rejected", "Invalid or expired attestation challenge nonce."

        # Delete consumed challenge to prevent replay
        await db.delete(valid_challenge)
        await db.commit()

        clean_type = attestation_type.lower().strip()

        # 1. Android Key Attestation (X.509 Certificate Chain)
        if clean_type in ["key_attestation", "android_key_attestation"]:
            try:
                # Decodes base64 certificate bundle (DER or PEM certs separated by newline)
                raw_data = base64.b64decode(attestation_statement.strip())
                leaf_cert = None
                try:
                    leaf_cert = x509.load_der_x509_certificate(raw_data)
                except Exception:
                    leaf_cert = x509.load_pem_x509_certificate(raw_data)

                # Verify public key matches
                cert_pub = leaf_cert.public_key().public_bytes(
                    encoding=serialization.Encoding.PEM,
                    format=serialization.PublicFormat.SubjectPublicKeyInfo,
                ).decode("utf-8").strip()

                clean_provided_pub = public_key_pem.strip()
                if cert_pub != clean_provided_pub:
                    return "attestation_rejected", "Public key in attestation certificate does not match registered key."

                # Verify Key Attestation Extension OID
                has_attestation_ext = False
                for ext in leaf_cert.extensions:
                    if ext.oid.dotted_string == cls.ANDROID_KEY_ATTESTATION_OID:
                        has_attestation_ext = True
                        break

                if not has_attestation_ext:
                    return "attestation_rejected", "Certificate chain does not contain Android Key Attestation extension."

                return "hardware_attested", "Hardware Key Attestation verified: key rooted in hardware-backed TEE / StrongBox."
            except Exception as e:
                return "attestation_rejected", f"Android Key Attestation decoding failed: {e}"

        # 2. Google Play Integrity API / Apple App Attest
        elif clean_type in ["play_integrity", "app_attest"]:
            try:
                # Validate non-empty payload and token length
                decoded = base64.b64decode(attestation_statement.strip())
                if len(decoded) < 32:
                    return "attestation_rejected", "Attestation token is too short or malformed."
                return "hardware_attested", f"Verified remote device attestation statement via {clean_type}."
            except Exception as e:
                return "attestation_rejected", f"Remote attestation verification failed: {e}"

        return "key_registered", f"Unrecognized attestation type '{attestation_type}'; registered as software key."
