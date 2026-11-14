import uuid
from datetime import datetime, timezone
from sqlalchemy import String, DateTime, ForeignKey, UniqueConstraint, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import UUID
from app.db.base import Base


class ConsumedNonce(Base):
    __tablename__ = "consumed_nonces"
    __table_args__ = (
        UniqueConstraint("session_id", "signature_hash", name="uq_session_signature_hash"),
        UniqueConstraint("session_id", "student_id", "nonce", name="uq_session_student_nonce"),
        Index("idx_consumed_nonces_session_student", "session_id", "student_id"),
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
    nonce: Mapped[str] = mapped_column(String(64), nullable=False)
    signature_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    consumed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    session = relationship("Session")
    student = relationship("User")
