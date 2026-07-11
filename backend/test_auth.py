import requests
import sys

# Login
res = requests.post("http://localhost:8000/api/auth/login", data={"username": "admin", "password": "admin"})
if res.status_code != 200:
    print("Login failed:", res.text)
    sys.exit(1)

token = res.json()["access_token"]
print("Token:", token)

# Get attendance
res2 = requests.get("http://localhost:8000/api/attendance", headers={"Authorization": f"Bearer {token}"})
print("Attendance status:", res2.status_code)
print("Attendance body:", res2.text)
