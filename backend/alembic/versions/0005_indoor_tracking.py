"""add indoor location tracking spatial model (hospitals/buildings/floors/rooms/wifi_access_points, camera position)

Revision ID: 0005_indoor_tracking
Revises: 7bcf537238f9
Create Date: 2026-09-13

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "0005_indoor_tracking"
down_revision: Union[str, Sequence[str], None] = "7bcf537238f9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
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

    op.create_table(
        "buildings",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column(
            "hospital_id", sa.Integer(), sa.ForeignKey("hospitals.id"), nullable=False
        ),
        sa.Column("name", sa.String(), nullable=False),
    )

    op.create_table(
        "floors",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column(
            "building_id", sa.Integer(), sa.ForeignKey("buildings.id"), nullable=False
        ),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("level", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("width_m", sa.Float(), nullable=False),
        sa.Column("height_m", sa.Float(), nullable=False),
        sa.Column("floorplan_image_path", sa.String(), nullable=True),
        sa.Column("published", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("origin_lat", sa.Float(), nullable=True),
        sa.Column("origin_lng", sa.Float(), nullable=True),
        sa.Column("geo_rotation_deg", sa.Float(), nullable=True),
        sa.Column("meters_per_unit", sa.Float(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now()
        ),
    )

    op.create_table(
        "rooms",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column("floor_id", sa.Integer(), sa.ForeignKey("floors.id"), nullable=False),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("room_type", sa.String(), nullable=False, server_default="room"),
        sa.Column("polygon", sa.Text(), nullable=False),
        sa.Column(
            "is_restricted", sa.Boolean(), nullable=False, server_default=sa.false()
        ),
    )

    op.create_table(
        "wifi_access_points",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column("floor_id", sa.Integer(), sa.ForeignKey("floors.id"), nullable=False),
        sa.Column("bssid", sa.String(), nullable=False, index=True),
        sa.Column("ssid", sa.String(), nullable=True),
        sa.Column("x", sa.Float(), nullable=False),
        sa.Column("y", sa.Float(), nullable=False),
        sa.Column("tx_power_dbm", sa.Float(), nullable=True),
        sa.Column("coverage_radius_m", sa.Float(), nullable=False, server_default="8.0"),
    )

    op.add_column("cameras", sa.Column("floor_id", sa.Integer(), sa.ForeignKey("floors.id"), nullable=True))
    op.add_column("cameras", sa.Column("x", sa.Float(), nullable=True))
    op.add_column("cameras", sa.Column("y", sa.Float(), nullable=True))
    op.add_column(
        "cameras",
        sa.Column("coverage_radius_m", sa.Float(), nullable=False, server_default="5.0"),
    )


def downgrade() -> None:
    op.drop_column("cameras", "coverage_radius_m")
    op.drop_column("cameras", "y")
    op.drop_column("cameras", "x")
    op.drop_column("cameras", "floor_id")
    op.drop_table("wifi_access_points")
    op.drop_table("rooms")
    op.drop_table("floors")
    op.drop_table("buildings")
    op.drop_table("hospitals")
