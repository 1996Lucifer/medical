import os
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://localhost/medical_agent")

def run_migration():
    engine = create_engine(DATABASE_URL)
    with engine.connect() as conn:
        print("Adding upper_embedding to staff table...")
        try:
            conn.execute(text("ALTER TABLE staff ADD COLUMN upper_embedding vector(512);"))
            print("Added to staff.")
        except Exception as e:
            print("Already exists or error:", e)
            
        print("Adding upper_embedding to staff_photos table...")
        try:
            conn.execute(text("ALTER TABLE staff_photos ADD COLUMN upper_embedding vector(512);"))
            print("Added to staff_photos.")
        except Exception as e:
            print("Already exists or error:", e)
        conn.commit()
    print("Migration complete.")

if __name__ == "__main__":
    run_migration()
