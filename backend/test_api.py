from fastapi.testclient import TestClient
from main import app
from database import SessionLocal
import models
from routers.auth import create_access_token

# We need a token
db = SessionLocal()
user = db.query(models.User).first()
if user:
    token = create_access_token(data={"sub": user.username, "role": user.role})
else:
    print("No user found")
    exit(1)
db.close()

client = TestClient(app)
resp = client.get("/api/cameras/rois/all/unique", headers={"Authorization": f"Bearer {token}"})
print(resp.status_code, resp.text)
