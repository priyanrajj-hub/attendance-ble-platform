import uuid
from datetime import datetime, timezone
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.auth.rbac import AuthenticatedUser, get_current_user
from app.db.session import get_db
from app.models.user import User
from app.models.device import Device
from app.schemas.device import (
    DeviceRegisterPayload,
    DeviceRegisterResponse,
    DevicePublicResponse,
    DeviceRevokePayload,
)
from app.services.device_verification_service import DeviceVerificationService

router = APIRouter(prefix="/devices", tags=["Device Registration & Attestation"])


@router.post(
    "/register",
    response_model=DeviceRegisterResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Register Device Cryptographic Public Key",
)
async def register_device(
    payload: DeviceRegisterPayload,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Registers a client device public key (ECDSA or RSA) backed by Android Keystore / iOS Keychain.
    Replaces any previously active device for this user by setting revoked_at.
    """
    # 1. Fetch user record
    u_stmt = select(User).where(User.firebase_uid == current_user.uid)
    u_res = await db.execute(u_stmt)
    user_record = u_res.scalar_one_or_none()
    if not user_record:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User profile not found.",
        )

    # 2. Compute public key fingerprint
    try:
        fingerprint = DeviceVerificationService.compute_fingerprint(payload.public_key_pem)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid public key PEM format: {e}",
        )

    platform_clean = payload.platform.lower().strip()
    if platform_clean not in ["android", "ios"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Platform must be either 'android' or 'ios'.",
        )

    now = datetime.now(timezone.utc)

    # 3. Revoke existing active devices for this user
    active_devices_stmt = select(Device).where(
        Device.user_id == user_record.id,
        Device.revoked_at.is_(None),
    )
    active_devices_res = await db.execute(active_devices_stmt)
    active_devices = active_devices_res.scalars().all()
    for dev in active_devices:
        dev.revoked_at = now

    # 4. Check if this exact public key is already registered
    existing_fp_stmt = select(Device).where(Device.public_key_fingerprint == fingerprint)
    existing_fp_res = await db.execute(existing_fp_stmt)
    existing_dev = existing_fp_res.scalar_one_or_none()
    if existing_dev:
        if existing_dev.user_id != user_record.id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="This device public key is already registered to another user.",
            )
        # Reactivate existing device
        existing_dev.revoked_at = None
        existing_dev.platform = platform_clean
        existing_dev.device_model = payload.device_model
        existing_dev.os_version = payload.os_version
        await db.commit()
        await db.refresh(existing_dev)
        return DeviceRegisterResponse(
            device_id=str(existing_dev.id),
            user_id=str(user_record.id),
            public_key_fingerprint=existing_dev.public_key_fingerprint,
            platform=existing_dev.platform,
            attestation_status=existing_dev.attestation_status,
            registered_at=existing_dev.registered_at,
            message="Device key re-activated successfully.",
        )

    # 5. Insert new Device
    new_device = Device(
        user_id=user_record.id,
        public_key_fingerprint=fingerprint,
        public_key_pem=payload.public_key_pem.strip(),
        platform=platform_clean,
        device_model=payload.device_model,
        os_version=payload.os_version,
        attestation_status="key_registered",
        registered_at=now,
    )
    db.add(new_device)
    await db.commit()
    await db.refresh(new_device)

    return DeviceRegisterResponse(
        device_id=str(new_device.id),
        user_id=str(user_record.id),
        public_key_fingerprint=new_device.public_key_fingerprint,
        platform=new_device.platform,
        attestation_status=new_device.attestation_status,
        registered_at=new_device.registered_at,
        message="Device public key registered successfully.",
    )


@router.get(
    "/me",
    response_model=Optional[DevicePublicResponse],
    status_code=status.HTTP_200_OK,
    summary="Get Current User's Active Registered Device",
)
async def get_my_device(
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Returns the caller's currently active registered hardware device.
    """
    u_stmt = select(User).where(User.firebase_uid == current_user.uid)
    u_res = await db.execute(u_stmt)
    user_record = u_res.scalar_one_or_none()
    if not user_record:
        raise HTTPException(status_code=404, detail="User profile not found.")

    device = await DeviceVerificationService.get_active_device(db, user_record.id)
    if not device:
        return None

    return DevicePublicResponse(
        id=str(device.id),
        user_id=str(device.user_id),
        public_key_fingerprint=device.public_key_fingerprint,
        platform=device.platform,
        device_model=device.device_model,
        os_version=device.os_version,
        attestation_status=device.attestation_status,
        registered_at=device.registered_at,
        revoked_at=device.revoked_at,
    )


@router.post(
    "/revoke",
    status_code=status.HTTP_200_OK,
    summary="Revoke Registered Device",
)
async def revoke_device(
    payload: DeviceRevokePayload,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Revokes a registered device key.
    """
    try:
        dev_uuid = uuid.UUID(payload.device_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid device ID format.")

    u_stmt = select(User).where(User.firebase_uid == current_user.uid)
    u_res = await db.execute(u_stmt)
    user_record = u_res.scalar_one_or_none()
    if not user_record:
        raise HTTPException(status_code=404, detail="User profile not found.")

    d_stmt = select(Device).where(Device.id == dev_uuid)
    d_res = await db.execute(d_stmt)
    device = d_res.scalar_one_or_none()
    if not device:
        raise HTTPException(status_code=404, detail="Device not found.")

    if device.user_id != user_record.id and current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Unauthorized to revoke this device.")

    device.revoked_at = datetime.now(timezone.utc)
    await db.commit()

    return {"status": "success", "message": f"Device {device.id} revoked successfully."}
