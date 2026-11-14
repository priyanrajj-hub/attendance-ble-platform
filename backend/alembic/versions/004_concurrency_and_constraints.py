"""004_concurrency_and_constraints

Revision ID: 004_concurrency_and_constraints
Revises: 003_audit_and_replay
Create Date: 2026-11-14 21:10:00.000000

"""
from alembic import op
import sqlalchemy as sa

revision = '004_concurrency_and_constraints'
down_revision = '003_audit_and_replay'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Add unique partial index to prevent duplicate pending disputes for (session_id, student_id)
    op.create_index(
        'uq_dispute_pending_session_student',
        'disputes',
        ['session_id', 'student_id'],
        unique=True,
        postgresql_where=sa.text("status = 'pending'"),
    )

    # 2. Update session status check constraint to include 'cancelled'
    op.drop_constraint('check_session_status', 'sessions', type_='check')
    op.create_check_constraint(
        'check_session_status',
        'sessions',
        "status IN ('active', 'closed', 'cancelled')",
    )


def downgrade() -> None:
    op.drop_constraint('check_session_status', 'sessions', type_='check')
    op.create_check_constraint(
        'check_session_status',
        'sessions',
        "status IN ('active', 'closed')",
    )
    op.drop_index('uq_dispute_pending_session_student', table_name='disputes')
