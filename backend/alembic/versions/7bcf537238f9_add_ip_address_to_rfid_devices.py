"""add ip_address to rfid_devices

Revision ID: 7bcf537238f9
Revises: 4a29336e9be2
Create Date: 2026-09-12 06:59:15.822415

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7bcf537238f9'
down_revision: Union[str, Sequence[str], None] = '4a29336e9be2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column("rfid_devices", sa.Column("ip_address", sa.String(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column("rfid_devices", "ip_address")
