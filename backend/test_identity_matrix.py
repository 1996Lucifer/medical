import requests
import numpy as np

# Let's check what the API returns for staff!
try:
    resp = requests.get("http://localhost:8000/api/staff")
    if resp.status_code == 200:
        data = resp.json()
        print("Staff fetched:", len(data))
        for s in data:
            emb = s.get("embedding", [])
            print("Staff:", s.get("name"), "has embedding length:", len(emb) if emb else 0)
    else:
        print("API error:", resp.status_code)
except Exception as e:
    print("Request failed:", e)
