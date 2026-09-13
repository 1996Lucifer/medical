"""add rfid card support

Revision ID: 4a29336e9be2
Revises: 0004_patient_doctor_calling
Create Date: 2026-09-09 21:49:31.337323

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '4a29336e9be2'
down_revision: Union[str, Sequence[str], None] = '0004_patient_doctor_calling'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


# NOTE: `alembic revision --autogenerate` also picked up a pile of unrelated
# schema drift already present between the DB and models.py (Text/VARCHAR
# type changes on consultations/medical_reports/security_alerts, nullability
# tweaks on security_alerts, missing indexes on
# person_verifications/staff_activity, and a cosmetic FK-name diff on
# attendance/security_alerts). None of that is part of this change, so it
# was stripped back out by hand — this migration only touches what RFID
# support and the new `attendance.source` column actually need.


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        'rfid_devices',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('label', sa.String(), nullable=False),
        sa.Column('device_key_hash', sa.String(), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('last_seen_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_rfid_devices_device_key_hash'), 'rfid_devices', ['device_key_hash'], unique=True)
    op.create_index(op.f('ix_rfid_devices_id'), 'rfid_devices', ['id'], unique=False)

    op.create_table(
        'rfid_cards',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('staff_id', sa.Integer(), nullable=False),
        sa.Column('token_hash', sa.String(), nullable=False),
        sa.Column('issued_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.Column('revoked_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['staff_id'], ['staff.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('staff_id'),
    )
    op.create_index(op.f('ix_rfid_cards_id'), 'rfid_cards', ['id'], unique=False)
    op.create_index(op.f('ix_rfid_cards_token_hash'), 'rfid_cards', ['token_hash'], unique=True)

    op.create_table(
        'rfid_enroll_sessions',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('device_id', sa.Integer(), nullable=False),
        sa.Column('staff_id', sa.Integer(), nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('consumed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.ForeignKeyConstraint(['device_id'], ['rfid_devices.id']),
        sa.ForeignKeyConstraint(['staff_id'], ['staff.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_rfid_enroll_sessions_id'), 'rfid_enroll_sessions', ['id'], unique=False)

    op.add_column(
        'attendance',
        sa.Column('source', sa.String(), server_default='face', nullable=False),
    )
    op.alter_column(
        'attendance',
        'confidence',
        existing_type=sa.DOUBLE_PRECISION(precision=53),
        nullable=True,
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.alter_column(
        'attendance',
        'confidence',
        existing_type=sa.DOUBLE_PRECISION(precision=53),
        nullable=False,
    )
    op.drop_column('attendance', 'source')

    op.drop_index(op.f('ix_rfid_enroll_sessions_id'), table_name='rfid_enroll_sessions')
    op.drop_table('rfid_enroll_sessions')

    op.drop_index(op.f('ix_rfid_cards_token_hash'), table_name='rfid_cards')
    op.drop_index(op.f('ix_rfid_cards_id'), table_name='rfid_cards')
    op.drop_table('rfid_cards')

    op.drop_index(op.f('ix_rfid_devices_id'), table_name='rfid_devices')
    op.drop_index(op.f('ix_rfid_devices_device_key_hash'), table_name='rfid_devices')
    op.drop_table('rfid_devices')
