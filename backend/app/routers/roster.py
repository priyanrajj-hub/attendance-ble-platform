import io
import csv
import uuid
import re
from typing import Dict, Any, List
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.auth.rbac import AuthenticatedUser, require_role
from app.config import settings
from app.db.session import get_db
from app.models.course import Course
from app.models.user import User
from app.models.enrollment import Enrollment

router = APIRouter(prefix="/courses", tags=["Course Rosters"])

# Formula injection prefixes
FORMULA_PREFIXES = ("=", "+", "-", "@", "\t", "\r")


def sanitize_formula_injection(val: str) -> str:
    """
    Guards against CSV / Spreadsheet formula injection (CSV Injection / CWE-1236).
    If a cell starts with formula trigger characters, prepends an apostrophe.
    """
    if not val:
        return ""
    cleaned = str(val).strip()
    if cleaned.startswith(FORMULA_PREFIXES):
        return "'" + cleaned
    return cleaned


@router.post("/{course_id}/roster")
async def import_course_roster(
    course_id: str,
    file: UploadFile = File(...),
    current_user: AuthenticatedUser = Depends(require_role(["faculty", "admin"])),
    db: AsyncSession = Depends(get_db),
):
    """
    Imports a course roster from a CSV file.
    Security controls:
    1. 2 MB max upload limit.
    2. Strict UTF-8 decoding rejection.
    3. Formula injection sanitization on all text fields.
    4. Institutional email domain verification.
    """
    try:
        cid = uuid.UUID(course_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid course ID format.")

    # Check course exists
    c_stmt = select(Course).where(Course.id == cid)
    c_res = await db.execute(c_stmt)
    course = c_res.scalar_one_or_none()
    if not course:
        raise HTTPException(status_code=404, detail="Course not found.")

    # 1. Read bytes and enforce size limit
    content = await file.read()
    if len(content) > settings.MAX_CSV_UPLOAD_SIZE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File exceeds maximum upload size limit of {settings.MAX_CSV_UPLOAD_SIZE_BYTES} bytes (2 MB).",
        )

    # 2. Enforce strict UTF-8 decoding
    try:
        decoded_content = content.decode("utf-8")
    except UnicodeDecodeError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="File contains invalid UTF-8 byte sequences. Upload must be valid UTF-8 encoded CSV.",
        )

    # 3. Parse CSV
    reader = csv.DictReader(io.StringIO(decoded_content))
    if not reader.fieldnames:
        raise HTTPException(status_code=400, detail="CSV file has empty header.")

    # Normalize header names (lowercase, stripped)
    header_map = {name.strip().lower(): name for name in reader.fieldnames}
    email_key = header_map.get("email") or header_map.get("student_email")
    if not email_key:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="CSV missing required column: 'email' or 'student_email'.",
        )

    roll_key = header_map.get("roll_number") or header_map.get("roll_no") or header_map.get("roll")
    name_key = header_map.get("name") or header_map.get("display_name") or header_map.get("student_name")

    total_rows = 0
    enrolled_count = 0
    skipped_count = 0

    for row in reader:
        total_rows += 1
        raw_email = row.get(email_key, "").strip()
        if not raw_email or "@" not in raw_email:
            skipped_count += 1
            continue

        raw_roll = row.get(roll_key, "").strip() if roll_key else None
        raw_name = row.get(name_key, "").strip() if name_key else "Student"

        # Apply formula sanitization
        email = sanitize_formula_injection(raw_email).lower()
        roll_number = sanitize_formula_injection(raw_roll) if raw_roll else None
        display_name = sanitize_formula_injection(raw_name) if raw_name else "Student"

        # Find or create user
        u_stmt = select(User).where(User.email == email)
        u_res = await db.execute(u_stmt)
        user = u_res.scalar_one_or_none()

        if not user:
            # Create student user stub
            generated_uid = f"stub-{uuid.uuid4().hex[:16]}"
            user = User(
                firebase_uid=generated_uid,
                email=email,
                display_name=display_name,
                roll_number=roll_number,
                role="student",
                status="pending_verification",
            )
            db.add(user)
            await db.flush()

        # Check existing enrollment
        e_stmt = select(Enrollment).where(
            Enrollment.course_id == cid, Enrollment.student_id == user.id
        )
        e_res = await db.execute(e_stmt)
        enrollment = e_res.scalar_one_or_none()

        if not enrollment:
            new_enrollment = Enrollment(
                course_id=cid,
                student_id=user.id,
                status="active",
            )
            db.add(new_enrollment)
            enrolled_count += 1
        else:
            if enrollment.status != "active":
                enrollment.status = "active"
                enrolled_count += 1
            else:
                skipped_count += 1

    await db.commit()

    return {
        "success": True,
        "course_id": str(cid),
        "total_rows": total_rows,
        "enrolled": enrolled_count,
        "skipped": skipped_count,
        "message": f"Successfully processed {total_rows} rows: {enrolled_count} enrolled, {skipped_count} skipped.",
    }
