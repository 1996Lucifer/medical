"""add staff_messages table (persisted staff-to-staff/doctor/patient chat)

Revision ID: 0009_staff_messages
Revises: 0008_add_staff_shift_hours
Create Date: 2026-09-18

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "0009_staff_messages"
down_revision: Union[str, Sequence[str], None] = "0008_add_staff_shift_hours"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "staff_messages",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column(
            "sender_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False
        ),
        sa.Column(
            "recipient_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False
        ),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
        ),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_staff_messages_sender_id", "staff_messages", ["sender_id"]
    )
    op.create_index(
        "ix_staff_messages_recipient_id", "staff_messages", ["recipient_id"]
    )
    op.create_index(
        "ix_staff_messages_created_at", "staff_messages", ["created_at"]
    )


def downgrade() -> None:
    op.drop_index("ix_staff_messages_created_at", table_name="staff_messages")
    op.drop_index("ix_staff_messages_recipient_id", table_name="staff_messages")
    op.drop_index("ix_staff_messages_sender_id", table_name="staff_messages")
    op.drop_table("staff_messages")
