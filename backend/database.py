import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.declarative import declarative_base
from dotenv import load_dotenv

load_dotenv(override=False)

# We will use PostgreSQL as requested
# Example connection string: postgresql://user:password@localhost/dbname
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@localhost:5433/medical_agent")

# if os.path.exists("/.dockerenv") or os.environ.get("DOCKER_CONTAINER") == "1":
#     DATABASE_URL = (
#         DATABASE_URL.replace("localhost:5433", "medical-db:5432")
#         .replace("127.0.0.1:5433", "medical-db:5432")
#         .replace("localhost:5432", "medical-db:5432")
#         .replace("127.0.0.1:5432", "medical-db:5432")
#     )

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
