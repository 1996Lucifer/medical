from database import SessionLocal
import models
db = SessionLocal()
records = db.query(models.Attendance).all()
for r in records:
    print(f"{r.id} | {r.staff_name} | {r.date} | Entry: {r.entry_time} | Last: {r.last_seen}")
