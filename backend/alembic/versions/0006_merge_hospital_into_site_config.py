"""merge hospitals table into site_config (single-hospital app already had this singleton)

Revision ID: 0006_merge_hospital_site_config
Revises: 0005_indoor_tracking
Create Date: 2026-09-13

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "0006_merge_hospital_site_config"
down_revision: Union[str, Sequence[str], None] = "0005_indoor_tracking"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("site_config", sa.Column("geofence_polygon", sa.Text(), nullable=True))
    op.add_column("site_config", sa.Column("working_hours_start", sa.Time(), nullable=True))
    op.add_column("site_config", sa.Column("working_hours_end", sa.Time(), nullable=True))

    # Carry over any data from the old hospitals singleton (id=1) into
    # site_config's singleton (id=1), if both happen to exist already.
    op.execute(
        """
        UPDATE site_config
        SET geofence_polygon = hospitals.geofence_polygon,
            working_hours_start = hospitals.working_hours_start,
            working_hours_end = hospitals.working_hours_end
        FROM hospitals
        WHERE site_config.id = 1 AND hospitals.id = 1
        """
    )

    op.drop_constraint("buildings_hospital_id_fkey", "buildings", type_="foreignkey")
    op.create_foreign_key(
        "buildings_hospital_id_fkey", "buildings", "site_config", ["hospital_id"], ["id"]
    )
    op.drop_table("hospitals")


def downgrade() -> None:
    op.create_table(
        "hospitals",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("address", sa.String(), nullable=True),
        sa.Column("geofence_polygon", sa.Text(), nullable=True),
        sa.Column("working_hours_start", sa.Time(), nullable=True),
        sa.Column("working_hours_end", sa.Time(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now()
        ),
    )
    op.drop_constraint("buildings_hospital_id_fkey", "buildings", type_="foreignkey")
    op.create_foreign_key(
        "buildings_hospital_id_fkey", "buildings", "hospitals", ["hospital_id"], ["id"]
    )
    op.drop_column("site_config", "working_hours_end")
    op.drop_column("site_config", "working_hours_start")
    op.drop_column("site_config", "geofence_polygon")
