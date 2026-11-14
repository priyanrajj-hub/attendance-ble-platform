"""003_audit_and_replay

Revision ID: 003_audit_and_replay
Revises: 002_add_challenges_table
Create Date: 2026-11-14 19:42:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '003_audit_and_replay'
down_revision = '002_add_challenges_table'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Add override_reason and marked_by to attendance_records
    op.add_column('attendance_records', sa.Column('override_reason', sa.Text(), nullable=True))
    op.add_column(
        'attendance_records',
        sa.Column(
            'marked_by',
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey('users.id', ondelete='SET NULL'),
            nullable=True,
        ),
    )

    # 2. Consumed Nonces (Per-student and signature replay protection)
    op.create_table(
        'consumed_nonces',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('session_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('sessions.id', ondelete='CASCADE'), nullable=False),
        sa.Column('student_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('nonce', sa.String(length=64), nullable=False),
        sa.Column('signature_hash', sa.String(length=64), nullable=False),
        sa.Column('consumed_at', sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint('session_id', 'signature_hash', name='uq_session_signature_hash'),
        sa.UniqueConstraint('session_id', 'student_id', 'nonce', name='uq_session_student_nonce'),
    )
    op.create_index('idx_consumed_nonces_session_student', 'consumed_nonces', ['session_id', 'student_id'])

    # 3. Device Attestation Challenges
    op.create_table(
        'device_attestation_challenges',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('challenge', sa.String(length=64), nullable=False, unique=True),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index('idx_attestation_challenges_user', 'device_attestation_challenges', ['user_id', 'challenge'])


def downgrade() -> None:
    op.drop_index('idx_attestation_challenges_user', table_name='device_attestation_challenges')
    op.drop_table('device_attestation_challenges')
    op.drop_index('idx_consumed_nonces_session_student', table_name='consumed_nonces')
    op.drop_table('consumed_nonces')
    op.drop_column('attendance_records', 'marked_by')
    op.drop_column('attendance_records', 'override_reason')
