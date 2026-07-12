from database import engine
from sqlalchemy import text

statements = [
    "ALTER TABLE staff ADD COLUMN photo_path VARCHAR;",
    "ALTER TABLE staff_photos ADD COLUMN photo_path VARCHAR;",
    "ALTER TABLE medical_reports ADD COLUMN file_path VARCHAR;",
    "ALTER TABLE medical_reports ADD COLUMN vitals_extracted VARCHAR;",
    "ALTER TABLE consultations ADD COLUMN prescription VARCHAR;"
]

with engine.connect() as conn:
    for stmt in statements:
        try:
            conn.execute(text(stmt))
            conn.commit()
            print(f"Successfully executed: {stmt}")
        except Exception as e:
            conn.rollback()
            print(f"Failed to execute {stmt}: {e}")

