import os
import sys
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from dotenv import load_dotenv

# Ensure we can import our backend modules
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from database import DATABASE_URL
import models
from camera.vision_service import VisionService

def backfill_upper_embeddings():
    print("Connecting to DB...")
    engine = create_engine(DATABASE_URL)
    Session = sessionmaker(bind=engine)
    db = Session()
    
    print("Initializing VisionService...")
    vision = VisionService()
    
    print("Backfilling Staff Table...")
    staff = db.query(models.Staff).all()
    for s in staff:
        if s.photo_path and os.path.exists(s.photo_path):
            print(f"  Processing staff '{s.name}'...")
            emb = vision.extract_upper_embedding(image_path=s.photo_path)
            if emb is not None:
                s.upper_embedding = emb.tolist()
                print(f"    -> Success!")
            else:
                print(f"    -> Failed to extract upper face from {s.photo_path}")
        else:
            print(f"  Skipping '{s.name}' (no valid photo_path)")
            
    print("Backfilling StaffPhoto Table...")
    photos = db.query(models.StaffPhoto).all()
    for p in photos:
        if p.photo_path and os.path.exists(p.photo_path):
            print(f"  Processing photo ID {p.id}...")
            emb = vision.extract_upper_embedding(image_path=p.photo_path)
            if emb is not None:
                p.upper_embedding = emb.tolist()
                print(f"    -> Success!")
            else:
                print(f"    -> Failed to extract upper face from {p.photo_path}")
                
    db.commit()
    db.close()
    print("Backfill complete!")

if __name__ == "__main__":
    backfill_upper_embeddings()
