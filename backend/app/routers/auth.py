import logging
import re
from typing import Optional
from pydantic import BaseModel, Field
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import firebase_admin
from firebase_admin import auth

from app.auth.firebase_auth import verify_firebase_id_token
from app.db.session import get_db
from app.models.user import User
from app.auth.rbac import security, HTTPAuthorizationCredentials

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["Authentication & Profile Sync"])

STUDENT_DOMAIN = "@ch.students.amrita.edu"
FACULTY_DOMAIN = "@ch.amrita.edu"


class ProfileSyncRequest(BaseModel):
    display_name: Optional[str] = None
    roll_number: Optional[str] = None
    # Note: 'role' and 'status' are strictly prohibited in the request body.
    # The server determines role authoritatively from the verified Firebase ID token.


class UserProfileResponse(BaseModel):
    uid: str
    email: str
    role: str
    status: str
    display_name: str
    roll_number: Optional[str] = None


@router.post("/sync-profile", response_model=UserProfileResponse, status_code=status.HTTP_200_OK)
async def sync_user_profile(
    payload: ProfileSyncRequest,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: AsyncSession = Depends(get_db),
):
    """
    Authoritative server-side profile initialization and role assignment.
    Zero-trust client model:
    1. Extracts and cryptographically verifies Firebase ID token.
    2. Validates that email has been verified.
    3. Derives role strictly from the verified email domain (not client input).
    4. Enforces initial status as 'pending_verification'.
    5. Persists to PostgreSQL users table and stamps custom claims.
    """
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Bearer authentication token.",
        )

    decoded = verify_firebase_id_token(credentials.credentials)
    uid = decoded.get("uid") or decoded.get("user_id")
    email = decoded.get("email", "").lower().strip()

    if not email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Firebase token does not contain an institutional email address.",
        )

    # Determine role authoritatively from verified institutional email domain
    if email.endswith(STUDENT_DOMAIN):
        derived_role = "student"
    elif email.endswith(FACULTY_DOMAIN):
        derived_role = "faculty"
    else:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Email domain '{email.split('@')[-1]}' is not authorized. Must be '{STUDENT_DOMAIN}' or '{FACULTY_DOMAIN}'.",
        )

    # Check if user already exists in PostgreSQL
    stmt = select(User).where(User.firebase_uid == uid)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    display_name = payload.display_name or decoded.get("name") or email.split("@")[0]
    roll_number = payload.roll_number

    if not user:
        # Initial creation - status strictly defaults to pending_verification
        user = User(
            firebase_uid=uid,
            email=email,
            display_name=display_name,
            roll_number=roll_number,
            role=derived_role,
            status="pending_verification",
        )
        db.add(user)
        # Stamp initial custom claims via Firebase Admin SDK
        try:
            auth.set_custom_user_claims(uid, {"role": derived_role, "status": "pending_verification"})
        except Exception as e:
            logger.warning("Could not stamp initial claims in offline/test environment: %s", e)
    else:
        # Existing user - update display name or roll number if provided, but NEVER allow client to alter role/status
        user.display_name = display_name
        if roll_number:
            user.roll_number = roll_number
        # Ensure role matches domain
        user.role = derived_role

    await db.commit()
    await db.refresh(user)

    return UserProfileResponse(
        uid=user.firebase_uid,
        email=user.email,
        role=user.role,
        status=user.status,
        display_name=user.display_name,
        roll_number=user.roll_number,
    )
