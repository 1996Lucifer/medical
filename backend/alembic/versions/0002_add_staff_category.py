"""add staff.category

Revision ID: 0002_staff_category
Revises: 0001_user_status_staff_link
Create Date: 2026-09-06

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "0002_staff_category"
down_revision: Union[str, Sequence[str], None] = "0001_user_status_staff_link"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "staff",
        sa.Column(
            "category",
            sa.String(),
            nullable=True,
            server_default="Medical Staff",
        ),
    )


def downgrade() -> None:
    op.drop_column("staff", "category")
