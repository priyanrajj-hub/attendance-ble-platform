import uuid
from typing import List, Optional
from pydantic import BaseModel
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from app.auth.rbac import AuthenticatedUser, get_current_user, require_role
from app.db.session import get_db
from app.models.course import Course
from app.models.user import User
from app.models.enrollment import Enrollment

router = APIRouter(prefix="/courses", tags=["Courses"])


class CourseCreate(BaseModel):
    code: str
    name: str
    term: str


class CourseResponse(BaseModel):
    id: str
    code: str
    name: str
    term: str
    faculty_id: str
    faculty_name: Optional[str] = None
    enrolled_count: int = 0


@router.get("", response_model=List[CourseResponse])
async def list_courses(
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Lists courses accessible to the authenticated user.
    - Admin: all courses
    - Faculty: courses taught
    - Student: courses enrolled
    """
    user_stmt = select(User).where(User.firebase_uid == current_user.uid)
    u_res = await db.execute(user_stmt)
    user_record = u_res.scalar_one_or_none()

    if not user_record and current_user.role != "admin":
        return []

    if current_user.role == "admin":
        stmt = select(Course)
    elif current_user.role == "faculty":
        stmt = select(Course).where(Course.faculty_id == user_record.id)
    else:
        # Student: join enrollments
        stmt = (
            select(Course)
            .join(Enrollment, Enrollment.course_id == Course.id)
            .where(Enrollment.student_id == user_record.id, Enrollment.status == "active")
        )

    result = await db.execute(stmt)
    courses = result.scalars().all()

    response = []
    for c in courses:
        # Count enrollments
        count_stmt = select(func.count(Enrollment.id)).where(
            Enrollment.course_id == c.id, Enrollment.status == "active"
        )
        count_res = await db.execute(count_stmt)
        enrolled_count = count_res.scalar_one() or 0

        # Faculty name
        fac_stmt = select(User.display_name).where(User.id == c.faculty_id)
        fac_res = await db.execute(fac_stmt)
        faculty_name = fac_res.scalar_one_or_none()

        response.append(
            CourseResponse(
                id=str(c.id),
                code=c.code,
                name=c.name,
                term=c.term,
                faculty_id=str(c.faculty_id),
                faculty_name=faculty_name,
                enrolled_count=enrolled_count,
            )
        )

    return response


@router.post("", response_model=CourseResponse, status_code=status.HTTP_201_CREATED)
async def create_course(
    payload: CourseCreate,
    current_user: AuthenticatedUser = Depends(require_role(["faculty", "admin"])),
    db: AsyncSession = Depends(get_db),
):
    """
    Creates a new course. Faculty or admin only.
    """
    user_stmt = select(User).where(User.firebase_uid == current_user.uid)
    u_res = await db.execute(user_stmt)
    user_record = u_res.scalar_one_or_none()

    if not user_record:
        # Auto-create faculty DB record if missing
        user_record = User(
            firebase_uid=current_user.uid,
            email=current_user.email,
            display_name=current_user.display_name or "Faculty Member",
            role=current_user.role,
            status="verified",
        )
        db.add(user_record)
        await db.flush()

    new_course = Course(
        code=payload.code.strip().upper(),
        name=payload.name.strip(),
        term=payload.term.strip(),
        faculty_id=user_record.id,
    )
    db.add(new_course)
    await db.commit()
    await db.refresh(new_course)

    return CourseResponse(
        id=str(new_course.id),
        code=new_course.code,
        name=new_course.name,
        term=new_course.term,
        faculty_id=str(new_course.faculty_id),
        faculty_name=user_record.display_name,
        enrolled_count=0,
    )


@router.get("/{course_id}", response_model=CourseResponse)
async def get_course_detail(
    course_id: str,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Returns course details.
    """
    try:
        cid = uuid.UUID(course_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid course ID format.")

    stmt = select(Course).where(Course.id == cid)
    res = await db.execute(stmt)
    c = res.scalar_one_or_none()

    if not c:
        raise HTTPException(status_code=404, detail="Course not found.")

    # Enforce strict resource authorization (Admin, Assigned Faculty, or Enrolled Student)
    if current_user.role != "admin":
        u_stmt = select(User).where(User.firebase_uid == current_user.uid)
        u_res = await db.execute(u_stmt)
        user_record = u_res.scalar_one_or_none()
        if not user_record:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="User record not found.")

        if current_user.role == "faculty":
            if c.faculty_id != user_record.id:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="You are not authorized to access details for another instructor's course.",
                )
        else:
            # Student: must be actively enrolled
            enr_check = select(Enrollment).where(
                Enrollment.course_id == c.id,
                Enrollment.student_id == user_record.id,
                Enrollment.status == "active",
            )
            enr_check_res = await db.execute(enr_check)
            if not enr_check_res.scalar_one_or_none():
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="You are not enrolled in this course.",
                )

    count_stmt = select(func.count(Enrollment.id)).where(
        Enrollment.course_id == c.id, Enrollment.status == "active"
    )
    count_res = await db.execute(count_stmt)
    enrolled_count = count_res.scalar_one() or 0

    fac_stmt = select(User.display_name).where(User.id == c.faculty_id)
    fac_res = await db.execute(fac_stmt)
    faculty_name = fac_res.scalar_one_or_none()

    return CourseResponse(
        id=str(c.id),
        code=c.code,
        name=c.name,
        term=c.term,
        faculty_id=str(c.faculty_id),
        faculty_name=faculty_name,
        enrolled_count=enrolled_count,
    )
