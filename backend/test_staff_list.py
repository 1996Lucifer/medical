import os
import sys
sys.path.append(os.path.dirname(__file__))

from database import SessionLocal
import routers.staff as staff
db = SessionLocal()
sl = staff.load_staff_list(db)
print("Staff list length:", len(sl))
if len(sl) > 0:
    print("Sample:", sl[0]["name"])
db.close()
