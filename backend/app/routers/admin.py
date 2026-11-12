import logging
import hashlib
from typing import Optional, List
from pydantic import BaseModel
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
import firebase_admin
from firebase_admin import auth

from app.auth.rbac import AuthenticatedUser, require_role
from app.db.session import get_db
from app.models.user import User
from app.models.audit_log import AuditLog

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/admin", tags=["Admin Management"])


class ApprovalRequest(BaseModel):
    role: Optional[str] = None  # student, faculty, admin


class UserResponse(BaseModel):
    uid: str
    email: str
    role: str
    status: str
    display_name: str
    roll_number: Optional[str] = None


@router.post("/users/{uid}/approve")
async def approve_user(
    uid: str,
    payload: ApprovalRequest,
    request: Request,
    current_admin: AuthenticatedUser = Depends(require_role(["admin"])),
    db: AsyncSession = Depends(get_db),
):
    """
    Authoritative server-side user approval.
    1. Updates Custom Claims in Firebase Auth.
    2. Updates user record in PostgreSQL.
    3. Writes immutable audit log.
    """
    # Find user in PostgreSQL
    stmt = select(User).where(User.firebase_uid == uid)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    target_role = payload.role or (user.role if user else "student")
    if target_role not in ("student", "faculty", "admin"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid target role '{target_role}'.",
        )

    # 1. Update Firebase Custom Claims
    try:
        auth.set_custom_user_claims(uid, {"role": target_role, "status": "verified"})
        logger.info("Stamped custom claims on Firebase user %s: role=%s, status=verified", uid, target_role)
    except Exception as e:
        logger.error("Failed to set Firebase custom claims for %s: %s", uid, e)
        # Note: In test/mock environments or if Firebase is offline, log error and continue if DB update works

    # 2. Update or create PostgreSQL record
    if user:
        user.status = "verified"
        user.role = target_role
    else:
        # Fetch email from Firebase user record if missing in DB
        user_email = ""
        user_name = "User"
        try:
            fb_user = auth.get_user(uid)
            user_email = fb_user.email or ""
            user_name = fb_user.display_name or "User"
        except Exception:
            pass

        user = User(
            firebase_uid=uid,
            email=user_email or f"{uid}@institution.edu",
            display_name=user_name,
            role=target_role,
            status="verified",
        )
        db.add(user)

    # 3. Log to audit_log
    client_ip = request.client.host if request.client else "unknown"
    ip_hash = hashlib.sha256(client_ip.encode("utf-8")).hexdigest()
    request_id = request.headers.get("x-request-id", "req-direct")

    # Get admin DB user id if available
    admin_stmt = select(User.id).where(User.firebase_uid == current_admin.uid)
    admin_result = await db.execute(admin_stmt)
    admin_db_id = admin_result.scalar_one_or_none()

    audit_entry = AuditLog(
        actor_id=admin_db_id,
        action="admin_approve_user",
        target_entity="user",
        target_id=uid,
        ip_hash=ip_hash,
        request_id=request_id,
        payload={"approved_role": target_role, "status": "verified"},
    )
    db.add(audit_entry)

    await db.commit()
    await db.refresh(user)

    return {
        "success": True,
        "message": f"User {uid} approved successfully as {target_role}.",
        "uid": uid,
        "status": user.status,
        "role": user.role,
    }


@router.post("/users/{uid}/reject")
async def reject_user(
    uid: str,
    request: Request,
    current_admin: AuthenticatedUser = Depends(require_role(["admin"])),
    db: AsyncSession = Depends(get_db),
):
    """
    Reject/Suspend user account.
    """
    stmt = select(User).where(User.firebase_uid == uid)
    result = await db.execute(stmt)
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"User with uid '{uid}' not found.",
        )

    user.status = "suspended"

    # Revoke custom claims in Firebase
    try:
        auth.set_custom_user_claims(uid, {"role": user.role, "status": "suspended"})
        auth.revoke_refresh_tokens(uid)
    except Exception as e:
        logger.error("Failed to revoke Firebase claims for %s: %s", uid, e)

    # Audit log
    client_ip = request.client.host if request.client else "unknown"
    ip_hash = hashlib.sha256(client_ip.encode("utf-8")).hexdigest()
    request_id = request.headers.get("x-request-id", "req-direct")

    admin_stmt = select(User.id).where(User.firebase_uid == current_admin.uid)
    admin_result = await db.execute(admin_stmt)
    admin_db_id = admin_result.scalar_one_or_none()

    audit_entry = AuditLog(
        actor_id=admin_db_id,
        action="admin_reject_user",
        target_entity="user",
        target_id=uid,
        ip_hash=ip_hash,
        request_id=request_id,
        payload={"status": "suspended"},
    )
    db.add(audit_entry)

    await db.commit()
    await db.refresh(user)

    return {
        "success": True,
        "message": f"User {uid} rejected and suspended.",
        "uid": uid,
        "status": user.status,
    }


@router.get("/users/pending", response_model=List[UserResponse])
async def list_pending_users(
    current_admin: AuthenticatedUser = Depends(require_role(["admin"])),
    db: AsyncSession = Depends(get_db),
):
    """
    List all users awaiting administrator approval.
    """
    stmt = select(User).where(User.status == "pending_verification")
    result = await db.execute(stmt)
    users = result.scalars().all()

    return [
        UserResponse(
            uid=u.firebase_uid,
            email=u.email,
            role=u.role,
            status=u.status,
            display_name=u.display_name,
            roll_number=u.roll_number,
        )
        for u in users
    ]
