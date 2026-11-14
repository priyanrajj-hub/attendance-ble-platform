import uuid
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.attendance_record import AttendanceRecord


class ReplayProtectionService:
    @classmethod
    async def get_existing_attendance(
        cls,
        db: AsyncSession,
        session_id: uuid.UUID,
        student_id: uuid.UUID,
    ) -> Optional[AttendanceRecord]:
        """
        Retrieves existing attendance record for a student in a session.
        """
        stmt = select(AttendanceRecord).where(
            AttendanceRecord.session_id == session_id,
            AttendanceRecord.student_id == student_id,
        )
        res = await db.execute(stmt)
        return res.scalar_one_or_none()
