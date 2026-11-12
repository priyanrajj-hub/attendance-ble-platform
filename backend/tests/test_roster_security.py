import pytest
import uuid
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from app.main import app
from app.auth.rbac import get_current_user, AuthenticatedUser
from app.models.course import Course
from app.models.user import User
from app.routers.roster import sanitize_formula_injection


def test_formula_injection_sanitization():
    """
    Unit test for CWE-1236 Formula Injection sanitization.
    """
    assert sanitize_formula_injection("=cmd|' /C calc'!A0") == "'=cmd|' /C calc'!A0"
    assert sanitize_formula_injection("+12345") == "'+12345"
    assert sanitize_formula_injection("-5+10") == "'-5+10"
    assert sanitize_formula_injection("@SUM(A1:A10)") == "'@SUM(A1:A10)"
    assert sanitize_formula_injection("\tTABBED") == "'\tTABBED"
    assert sanitize_formula_injection("\rRETURN") == "'\rRETURN"
    assert sanitize_formula_injection("normal_student@amrita.edu") == "normal_student@amrita.edu"


@pytest.mark.asyncio
async def test_csv_upload_size_limit_rejected(
    client: AsyncClient, mock_faculty_user: AuthenticatedUser
):
    """
    Ensure CSV uploads strictly exceeding 2 MB are rejected with HTTP 413.
    """
    app.dependency_overrides[get_current_user] = lambda: mock_faculty_user

    # Generate oversized payload (> 2MB)
    oversized_data = b"email,name\n" + b"student@amrita.edu,Test Student\n" * 80000
    assert len(oversized_data) > 2 * 1024 * 1024

    course_id = str(uuid.uuid4())
    files = {"file": ("roster.csv", oversized_data, "text/csv")}

    res = await client.post(f"/api/v1/courses/{course_id}/roster", files=files)
    assert res.status_code == 413
    assert "exceeds maximum upload size limit" in res.json()["detail"]

    app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_csv_malformed_utf8_rejected(
    client: AsyncClient, mock_faculty_user: AuthenticatedUser, db_session: AsyncSession
):
    """
    Ensure invalid UTF-8 byte sequences are rejected with HTTP 400.
    """
    app.dependency_overrides[get_current_user] = lambda: mock_faculty_user

    # Create dummy course
    uid_suffix = uuid.uuid4().hex[:8]
    faculty = User(
        firebase_uid=f"fac-utf8-{uid_suffix}",
        email=f"fac_utf8_{uid_suffix}@ch.amrita.edu",
        display_name="Dr. UTF8",
        role="faculty",
        status="verified",
    )
    db_session.add(faculty)
    await db_session.flush()

    course = Course(
        code=f"CSE{uid_suffix[:4].upper()}",
        name="Security Analysis",
        term="Fall 2026",
        faculty_id=faculty.id,
    )
    db_session.add(course)
    await db_session.commit()

    # Invalid non-UTF8 sequence (e.g. invalid continuation byte 0xFF, 0xFE)
    malformed_bytes = b"email,name\nstudent@amrita.edu,\xff\xfeBadBytes\n"
    files = {"file": ("roster.csv", malformed_bytes, "text/csv")}

    res = await client.post(f"/api/v1/courses/{str(course.id)}/roster", files=files)
    assert res.status_code == 400
    assert "invalid UTF-8 byte sequences" in res.json()["detail"]

    app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_csv_valid_import_and_formula_defense(
    client: AsyncClient, mock_faculty_user: AuthenticatedUser, db_session: AsyncSession
):
    """
    Ensure valid CSV imports successfully and formula injection triggers are disarmed.
    """
    app.dependency_overrides[get_current_user] = lambda: mock_faculty_user

    # Create course
    uid_suffix = uuid.uuid4().hex[:8]
    faculty = User(
        firebase_uid=f"fac-roster-{uid_suffix}",
        email=f"fac_roster_{uid_suffix}@ch.amrita.edu",
        display_name="Dr. Roster",
        role="faculty",
        status="verified",
    )
    db_session.add(faculty)
    await db_session.flush()

    course = Course(
        code=f"CSE{uid_suffix[:4].upper()}",
        name="Embedded Systems",
        term="Fall 2026",
        faculty_id=faculty.id,
    )
    db_session.add(course)
    await db_session.commit()

    # CSV containing normal student and formula injection attempt
    csv_content = (
        "email,roll_number,name\n"
        "cb.en.u4cse22010@ch.students.amrita.edu,CSE22010,Karthik S\n"
        "cb.en.u4cse22011@ch.students.amrita.edu,=SUM(1+1),@EvilAdmin\n"
    ).encode("utf-8")

    files = {"file": ("roster.csv", csv_content, "text/csv")}
    res = await client.post(f"/api/v1/courses/{str(course.id)}/roster", files=files)

    assert res.status_code == 200
    data = res.json()
    assert data["success"] is True
    assert data["enrolled"] == 2

    app.dependency_overrides.clear()
