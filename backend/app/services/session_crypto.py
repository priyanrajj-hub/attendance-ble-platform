import os
import hashlib
from typing import Optional
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from app.config import settings


class SessionCrypto:
    """
    AES-256-GCM Envelope Encryption for Session Secrets at Rest.
    Eliminates plaintext secret storage in PostgreSQL (sessions.secret_hash).
    Key is derived from server SECRET_KEY using SHA-256.
    """

    @classmethod
    def _get_kek(cls) -> bytes:
        return hashlib.sha256(settings.SECRET_KEY.encode("utf-8")).digest()

    @classmethod
    def encrypt_session_secret(cls, ephemeral_token_hex: str) -> str:
        """
        Encrypts the 256-bit ephemeral session secret using AES-256-GCM.
        Produces an authenticated ciphertext string in format:
        enc:<nonce_hex>:<ciphertext_and_tag_hex>
        """
        kek = cls._get_kek()
        aesgcm = AESGCM(kek)
        nonce = os.urandom(12)  # Standard 96-bit GCM nonce

        # Convert 64-char hex string to 32 bytes for compact storage
        try:
            raw_bytes = bytes.fromhex(ephemeral_token_hex)
        except ValueError:
            raw_bytes = ephemeral_token_hex.encode("utf-8")

        ct_and_tag = aesgcm.encrypt(nonce, raw_bytes, None)
        return f"enc:{nonce.hex()}:{ct_and_tag.hex()}"

    @classmethod
    def decrypt_session_secret(cls, stored_value: str) -> str:
        """
        Decrypts an encrypted session secret string in-memory.
        If the stored value does not start with 'enc:', returns it as-is for backward compatibility.
        """
        if not stored_value or not stored_value.startswith("enc:"):
            return stored_value

        try:
            parts = stored_value.split(":")
            if len(parts) != 3:
                raise ValueError("Malformed encrypted secret format")

            nonce = bytes.fromhex(parts[1])
            ct_and_tag = bytes.fromhex(parts[2])

            kek = cls._get_kek()
            aesgcm = AESGCM(kek)
            decrypted_bytes = aesgcm.decrypt(nonce, ct_and_tag, None)

            # If it was 32 raw bytes from a 64-hex token, return hex string
            if len(decrypted_bytes) == 32:
                return decrypted_bytes.hex()
            return decrypted_bytes.decode("utf-8")
        except Exception as e:
            raise ValueError(f"Failed to decrypt session secret: {e}") from e
