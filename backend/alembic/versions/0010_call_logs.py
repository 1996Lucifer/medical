"""add call_logs table (persisted call history for the calling feature)

Revision ID: 0010_call_logs
Revises: 0009_staff_messages
Create Date: 2026-09-19

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "0010_call_logs"
down_revision: Union[str, Sequence[str], None] = "0009_staff_messages"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "call_logs",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column(
            "caller_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False
        ),
        sa.Column(
            "callee_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False
        ),
        sa.Column("mode", sa.String(), nullable=False, server_default="audio"),
        sa.Column("status", sa.String(), nullable=False, server_default="ringing"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
        ),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_call_logs_caller_id", "call_logs", ["caller_id"])
    op.create_index("ix_call_logs_callee_id", "call_logs", ["callee_id"])
    op.create_index("ix_call_logs_status", "call_logs", ["status"])
    op.create_index("ix_call_logs_created_at", "call_logs", ["created_at"])


def downgrade() -> None:
    op.drop_index("ix_call_logs_created_at", table_name="call_logs")
    op.drop_index("ix_call_logs_status", table_name="call_logs")
    op.drop_index("ix_call_logs_callee_id", table_name="call_logs")
    op.drop_index("ix_call_logs_caller_id", table_name="call_logs")
    op.drop_table("call_logs")
