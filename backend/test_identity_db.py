import os
import sys
sys.path.append(os.path.dirname(__file__))

from database import SessionLocal
import models
import json
db = SessionLocal()
staffs = db.query(models.Staff).all()
print("Total staff in DB:", len(staffs))
for s in staffs:
    emb = json.loads(s.face_embedding) if s.face_embedding else []
    print("Staff:", s.name, "Embedding len:", len(emb))
db.close()
