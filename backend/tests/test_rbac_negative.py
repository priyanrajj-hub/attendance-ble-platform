import pytest
from httpx import AsyncClient
from app.main import app
from app.auth.rbac import get_current_user, AuthenticatedUser


@pytest.mark.asyncio
async def test_unauthenticated_requests_blocked(client: AsyncClient):
    """
    Ensure all sensitive endpoints reject unauthenticated requests with HTTP 401.
    """
    endpoints = [
        ("GET", "/api/v1/admin/users/pending"),
        ("GET", "/api/v1/courses"),
        ("GET", "/api/v1/sessions/active"),
        ("POST", "/api/v1/sessions/start"),
    ]
    for method, url in endpoints:
        if method == "GET":
            res = await client.get(url)
        else:
            res = await client.post(url, json={})
        assert res.status_code == 401, f"Expected 401 on {method} {url}, got {res.status_code}"


@pytest.mark.asyncio
async def test_unverified_account_blocked_from_protected_endpoints(
    client: AsyncClient, mock_unverified_student_user: AuthenticatedUser
):
    """
    Ensure pending_verification accounts are rejected with HTTP 403 on role-guarded endpoints.
    """
    app.dependency_overrides[get_current_user] = lambda: mock_unverified_student_user

    res = await client.post(
        "/api/v1/courses",
        json={"code": "CSE312", "name": "Distributed Systems", "term": "Fall 2026"},
    )
    assert res.status_code == 403
    assert "Verification is required" in res.json()["detail"]

    app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_student_blocked_from_admin_and_faculty_actions(
    client: AsyncClient, mock_student_user: AuthenticatedUser
):
    """
    Negative RBAC: Verified student cannot access admin or faculty endpoints.
    """
    app.dependency_overrides[get_current_user] = lambda: mock_student_user

    # Student calling admin user approval
    res_admin = await client.post(
        "/api/v1/admin/users/fake-uid/approve",
        json={"role": "faculty"},
    )
    assert res_admin.status_code == 403
    assert "role 'student' not permitted" in res_admin.json()["detail"]

    # Student calling course creation
    res_course = await client.post(
        "/api/v1/courses",
        json={"code": "CSE312", "name": "Distributed Systems", "term": "Fall 2026"},
    )
    assert res_course.status_code == 403
    assert "role 'student' not permitted" in res_course.json()["detail"]

    # Student calling session start
    res_session = await client.post(
        "/api/v1/sessions/start",
        json={
            "course_id": "00000000-0000-0000-0000-000000000001",
            "room_label": "AB3-204",
        },
    )
    assert res_session.status_code == 403
    assert "role 'student' not permitted" in res_session.json()["detail"]

    app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_faculty_blocked_from_admin_endpoints(
    client: AsyncClient, mock_faculty_user: AuthenticatedUser
):
    """
    Negative RBAC: Verified faculty cannot approve users or access admin routes.
    """
    app.dependency_overrides[get_current_user] = lambda: mock_faculty_user

    res = await client.get("/api/v1/admin/users/pending")
    assert res.status_code == 403
    assert "role 'faculty' not permitted" in res.json()["detail"]

    app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_admin_access_allowed(
    client: AsyncClient, mock_admin_user: AuthenticatedUser
):
    """
    Positive RBAC: Verified admin can list pending users.
    """
    app.dependency_overrides[get_current_user] = lambda: mock_admin_user

    res = await client.get("/api/v1/admin/users/pending")
    assert res.status_code == 200
    assert isinstance(res.json(), list)

    app.dependency_overrides.clear()
