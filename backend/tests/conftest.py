import pytest
import pytest_asyncio
from typing import AsyncGenerator
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.pool import NullPool

from app.main import app
from app.config import settings
from app.db.session import get_db
from app.auth.rbac import AuthenticatedUser, get_current_user

# Test Database Engine with NullPool to prevent event loop connection leakage
test_engine = create_async_engine(
    settings.DATABASE_URL,
    echo=False,
    future=True,
    poolclass=NullPool,
)

TestingSessionLocal = async_sessionmaker(
    bind=test_engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)


@pytest_asyncio.fixture
async def db_session() -> AsyncGenerator[AsyncSession, None]:
    async with TestingSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()


@pytest_asyncio.fixture
async def client(db_session: AsyncSession) -> AsyncGenerator[AsyncClient, None]:
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c

    app.dependency_overrides.clear()


# User Fixtures
@pytest.fixture
def mock_admin_user() -> AuthenticatedUser:
    return AuthenticatedUser(
        uid="admin-test-001",
        email="admin@amrita.edu",
        role="admin",
        status="verified",
        display_name="Institutional Administrator",
        claims={"role": "admin", "status": "verified"},
    )


@pytest.fixture
def mock_faculty_user() -> AuthenticatedUser:
    return AuthenticatedUser(
        uid="faculty-test-002",
        email="rajesh@ch.amrita.edu",
        role="faculty",
        status="verified",
        display_name="Dr. Rajesh Kumar",
        claims={"role": "faculty", "status": "verified"},
    )


@pytest.fixture
def mock_student_user() -> AuthenticatedUser:
    return AuthenticatedUser(
        uid="student-test-003",
        email="cb.en.u4cse22001@ch.students.amrita.edu",
        role="student",
        status="verified",
        display_name="Arun Sundaram",
        claims={"role": "student", "status": "verified"},
    )


@pytest.fixture
def mock_unverified_student_user() -> AuthenticatedUser:
    return AuthenticatedUser(
        uid="student-unverified-004",
        email="cb.en.u4cse22999@ch.students.amrita.edu",
        role="student",
        status="pending_verification",
        display_name="Pending Student",
        claims={"role": "student", "status": "pending_verification"},
    )
