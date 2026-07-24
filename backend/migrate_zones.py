"""
Migration script to add zone_type column to camera_rois table
and create person_verifications table for the zone-based compliance engine.
"""
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from database import engine
from sqlalchemy import text, inspect


def migrate():
    """Run additive schema migration for zone-based compliance."""
    inspector = inspect(engine)

    with engine.connect() as conn:
        # 1. Add zone_type column to camera_rois if it doesn't exist
        existing_cols = [col["name"] for col in inspector.get_columns("camera_rois")]
        if "zone_type" not in existing_cols:
            print("[Migration] Adding 'zone_type' column to camera_rois...")
            conn.execute(
                text(
                    "ALTER TABLE camera_rois "
                    "ADD COLUMN zone_type VARCHAR NOT NULL DEFAULT 'observation'"
                )
            )
            print("[Migration] ✅ zone_type column added (default='observation').")
        else:
            print("[Migration] zone_type column already exists. Skipping.")

        # 2. Create person_verifications table if it doesn't exist
        existing_tables = inspector.get_table_names()
        if "person_verifications" not in existing_tables:
            print("[Migration] Creating 'person_verifications' table...")
            conn.execute(
                text(
                    """
                    CREATE TABLE person_verifications (
                        id SERIAL PRIMARY KEY,
                        staff_name VARCHAR NOT NULL,
                        camera_id INTEGER REFERENCES cameras(id),
                        has_mask BOOLEAN DEFAULT FALSE,
                        has_left_glove BOOLEAN DEFAULT FALSE,
                        has_right_glove BOOLEAN DEFAULT FALSE,
                        is_verified BOOLEAN DEFAULT FALSE,
                        confidence FLOAT,
                        verified_at TIMESTAMPTZ,
                        expires_at TIMESTAMPTZ,
                        created_at TIMESTAMPTZ DEFAULT NOW()
                    )
                    """
                )
            )
            conn.execute(
                text(
                    "CREATE INDEX ix_person_verifications_staff_name "
                    "ON person_verifications (staff_name)"
                )
            )
            print("[Migration] ✅ person_verifications table created.")
        else:
            print("[Migration] person_verifications table already exists. Skipping.")

        conn.commit()
        print("[Migration] ✅ All migrations completed successfully.")


if __name__ == "__main__":
    migrate()
