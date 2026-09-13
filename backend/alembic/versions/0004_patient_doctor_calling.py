"""add patients.user_id and consultations.staff_id (patient portal + calling)

Revision ID: 0004_patient_doctor_calling
Revises: 0003_fix_agent_memory_dim
Create Date: 2026-09-09

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "0004_patient_doctor_calling"
down_revision: Union[str, Sequence[str], None] = "0003_fix_agent_memory_dim"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "patients",
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
    )
    op.add_column(
        "consultations",
        sa.Column("staff_id", sa.Integer(), sa.ForeignKey("staff.id"), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("consultations", "staff_id")
    op.drop_column("patients", "user_id")
