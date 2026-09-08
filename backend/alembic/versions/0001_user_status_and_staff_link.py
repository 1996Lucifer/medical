"""add users.status and staff.user_id

Revision ID: 0001_user_status_staff_link
Revises:
Create Date: 2026-09-06

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "0001_user_status_staff_link"
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "status",
            sa.String(),
            nullable=False,
            server_default="active",
        ),
    )
    op.add_column(
        "staff",
        sa.Column("user_id", sa.Integer(), nullable=True),
    )
    op.create_foreign_key(
        "fk_staff_user_id_users",
        "staff",
        "users",
        ["user_id"],
        ["id"],
    )


def downgrade() -> None:
    op.drop_constraint("fk_staff_user_id_users", "staff", type_="foreignkey")
    op.drop_column("staff", "user_id")
    op.drop_column("users", "status")
