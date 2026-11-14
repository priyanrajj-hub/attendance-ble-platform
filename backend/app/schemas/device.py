import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, Field


class DeviceRegisterPayload(BaseModel):
    public_key_pem: str = Field(..., description="Asymmetric public key in PEM format")
    platform: str = Field(..., description="Operating system platform ('android' or 'ios')")
    device_model: Optional[str] = Field(None, description="Hardware model name")
    os_version: Optional[str] = Field(None, description="OS build version")


class DeviceRegisterResponse(BaseModel):
    device_id: str
    user_id: str
    public_key_fingerprint: str
    platform: str
    attestation_status: str
    registered_at: datetime
    message: str


class DevicePublicResponse(BaseModel):
    id: str
    user_id: str
    public_key_fingerprint: str
    platform: str
    device_model: Optional[str]
    os_version: Optional[str]
    attestation_status: str
    registered_at: datetime
    revoked_at: Optional[datetime]


class DeviceRevokePayload(BaseModel):
    device_id: str
    reason: Optional[str] = None
