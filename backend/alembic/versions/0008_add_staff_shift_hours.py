"""add staff shift_start/shift_end (per-staff expected shift hours)

Revision ID: 0008_add_staff_shift_hours
Revises: 0007_drop_dead_tables
Create Date: 2026-09-13

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "0008_add_staff_shift_hours"
down_revision: Union[str, Sequence[str], None] = "0007_drop_dead_tables"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("staff", sa.Column("shift_start", sa.Time(), nullable=True))
    op.add_column("staff", sa.Column("shift_end", sa.Time(), nullable=True))


def downgrade() -> None:
    op.drop_column("staff", "shift_end")
    op.drop_column("staff", "shift_start")
