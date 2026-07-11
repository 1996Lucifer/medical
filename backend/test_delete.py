import os
import sys
from database import SessionLocal
import models
from routers.staff import delete_staff

db = SessionLocal()
try:
    print("Testing get_staff")
    staff = db.query(models.Staff).first()
    if staff:
        print("Found staff", staff.id)
        delete_staff(staff.id, db)
        print("Deleted!")
    else:
        print("No staff")
except Exception as e:
    import traceback
    traceback.print_exc()
