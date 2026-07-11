from database import engine
from sqlalchemy import text

with engine.connect() as conn:
    try:
        conn.execute(text("ALTER TABLE staff ADD COLUMN photo_path VARCHAR;"))
        print("Added photo_path to staff")
    except Exception as e:
        print(f"staff alter failed: {e}")
        
    try:
        conn.execute(text("ALTER TABLE staff_photos ADD COLUMN photo_path VARCHAR;"))
        print("Added photo_path to staff_photos")
    except Exception as e:
        print(f"staff_photos alter failed: {e}")
        
    conn.commit()
