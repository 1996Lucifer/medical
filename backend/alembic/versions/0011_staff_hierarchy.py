"""add staff reporting hierarchy (is_head, department, reports_to_id)

Revision ID: 0011_staff_hierarchy
Revises: 0010_call_logs
Create Date: 2026-09-19

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "0011_staff_hierarchy"
down_revision: Union[str, Sequence[str], None] = "0010_call_logs"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "staff",
        sa.Column(
            "is_head", sa.Boolean(), nullable=False, server_default="false"
        ),
    )
    op.add_column("staff", sa.Column("department", sa.String(), nullable=True))
    op.add_column(
        "staff",
        sa.Column(
            "reports_to_id", sa.Integer(), sa.ForeignKey("staff.id"), nullable=True
        ),
    )
    op.create_index("ix_staff_reports_to_id", "staff", ["reports_to_id"])
    op.create_index("ix_staff_department", "staff", ["department"])


def downgrade() -> None:
    op.drop_index("ix_staff_department", table_name="staff")
    op.drop_index("ix_staff_reports_to_id", table_name="staff")
    op.drop_column("staff", "reports_to_id")
    op.drop_column("staff", "department")
    op.drop_column("staff", "is_head")
