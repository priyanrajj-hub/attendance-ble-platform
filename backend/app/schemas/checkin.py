import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class CheckInPayload(BaseModel):
    session_id: str = Field(..., description="UUID of the attendance session")
    ephemeral_nonce: str = Field(..., description="Rotating challenge code observed via BLE beacon")
    observed_rssi: int = Field(..., description="Observed RSSI value in dBm")
    client_timestamp: Optional[int] = Field(None, description="Unix timestamp in milliseconds at sighting")
    public_key_fingerprint: Optional[str] = Field(None, description="SHA-256 fingerprint of student's device public key")
    signature: Optional[str] = Field(None, description="Cryptographic signature over session_id:ephemeral_nonce:client_timestamp")


class CheckInResponse(BaseModel):
    attendance_id: str
    session_id: str
    student_id: str
    status: str
    method: str
    verified_at: datetime
    already_marked: bool
    signature_verified: bool
    message: str
