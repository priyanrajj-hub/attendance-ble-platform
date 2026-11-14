import uuid
from datetime import datetime, timezone
from typing import Optional
from sqlalchemy import String, Integer, Boolean, DateTime, ForeignKey, CheckConstraint, UniqueConstraint, Index, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.db.base import Base


class AttendanceRecord(Base):
    __tablename__ = "attendance_records"
    __table_args__ = (
        CheckConstraint(
            "method IN ('ble_signed_nonce', 'faculty_manual_override')",
            name="check_attendance_method",
        ),
        CheckConstraint(
            "status IN ('present', 'disputed', 'revoked')", name="check_attendance_status"
        ),
        UniqueConstraint("session_id", "student_id", name="uq_session_student"),
        Index("idx_attendance_student", "student_id", "verified_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    session_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("sessions.id", ondelete="CASCADE"), nullable=False
    )
    student_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    device_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("devices.id", ondelete="RESTRICT"), nullable=True
    )
    method: Mapped[str] = mapped_column(String(32), nullable=False)
    rssi_observed: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    signature_verified: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    verified_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    status: Mapped[str] = mapped_column(String(32), default="present", nullable=False)
    override_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    marked_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    session = relationship("Session", back_populates="attendance_records")
    student = relationship("User", foreign_keys=[student_id])
    device = relationship("Device", foreign_keys=[device_id])
    marker = relationship("User", foreign_keys=[marked_by])
