from database import SessionLocal
import models

db = SessionLocal()
rois = db.query(models.CameraROI).all()
print("All ROIs:")
for r in rois:
    print(r.id, r.camera_id, r.zone_name, r.points)
db.close()
