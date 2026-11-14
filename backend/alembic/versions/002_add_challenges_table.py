"""002_add_challenges_table

Revision ID: 002_add_challenges_table
Revises: 001_initial_schema
Create Date: 2026-11-14 17:15:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '002_add_challenges_table'
down_revision = '001_initial_schema'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'challenges',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('session_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('sessions.id', ondelete='CASCADE'), nullable=False),
        sa.Column('challenge_code', sa.String(length=64), nullable=False),
        sa.Column('time_step', sa.Integer(), nullable=False),
        sa.Column('valid_from', sa.DateTime(timezone=True), nullable=False),
        sa.Column('valid_until', sa.DateTime(timezone=True), nullable=False),
        sa.Column('status', sa.String(length=32), nullable=False, server_default='active'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint("status IN ('active', 'consumed', 'expired')", name='check_challenge_status')
    )
    op.create_index('idx_challenges_session_code', 'challenges', ['session_id', 'challenge_code'])


def downgrade() -> None:
    op.drop_index('idx_challenges_session_code', table_name='challenges')
    op.drop_table('challenges')
