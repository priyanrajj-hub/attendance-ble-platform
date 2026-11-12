from typing import List, Optional, Dict, Any
from pydantic import BaseModel
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.auth.firebase_auth import verify_firebase_id_token
from app.db.session import get_db
from app.models.user import User

security = HTTPBearer(auto_error=False)


class AuthenticatedUser(BaseModel):
    uid: str
    email: str
    role: str
    status: str
    institution_id: Optional[str] = None
    display_name: Optional[str] = None
    claims: Dict[str, Any] = {}


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: AsyncSession = Depends(get_db),
) -> AuthenticatedUser:
    """
    Extracts and verifies the Firebase Bearer token.
    Populates user role and status from custom claims, with a database fallback.
    """
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Bearer authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = credentials.credentials
    decoded = verify_firebase_id_token(token)

    uid = decoded.get("uid") or decoded.get("user_id")
    email = decoded.get("email", "")
    role = decoded.get("role")
    user_status = decoded.get("status")
    institution_id = decoded.get("institution_id")

    # If role or status is not in token custom claims, read from Postgres user record
    if not role or not user_status:
        stmt = select(User).where(User.firebase_uid == uid)
        result = await db.execute(stmt)
        user_record = result.scalar_one_or_none()
        if user_record:
            role = role or user_record.role
            user_status = user_status or user_record.status
            institution_id = institution_id or (str(user_record.institution_id) if user_record.institution_id else None)
        else:
            # New user default fallback based on institutional domain
            if email.endswith("@ch.students.amrita.edu"):
                role = role or "student"
            elif email.endswith("@ch.amrita.edu"):
                role = role or "faculty"
            else:
                role = role or "student"
            user_status = user_status or "pending_verification"

    return AuthenticatedUser(
        uid=uid,
        email=email,
        role=role,
        status=user_status,
        institution_id=institution_id,
        display_name=decoded.get("name"),
        claims=decoded,
    )


def require_role(allowed_roles: List[str]):
    """
    FastAPI dependency factory enforcing RBAC and verified account status.
    Blocks unverified and unauthorized accounts with 403 Forbidden.
    """
    async def role_checker(
        current_user: AuthenticatedUser = Depends(get_current_user),
    ) -> AuthenticatedUser:
        if current_user.status != "verified":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Account status is '{current_user.status}'. Verification is required.",
            )
        if current_user.role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Access forbidden: role '{current_user.role}' not permitted for this resource.",
            )
        return current_user

    return role_checker
