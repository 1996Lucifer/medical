import requests
from requests.auth import HTTPBasicAuth, HTTPDigestAuth

ip = "192.168.1.29"
user = "admin"
password = "133033CC"

paths = [
    "/cgi-bin/snapshot.cgi",
    "/onvif/snapshot",
    "/snapshot",
    "/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=wuuPhik9wEp120"
]

print("Testing HTTP snapshots...")
for p in paths:
    url = f"http://{ip}{p}"
    print(f"\nTrying {url}")
    try:
        # Try basic auth
        r = requests.get(url, auth=HTTPBasicAuth(user, password), timeout=3)
        print(f"Basic Auth -> Status: {r.status_code}")
        if r.status_code == 200:
            print("SUCCESS with Basic Auth!")
            break
            
        # Try digest auth
        r = requests.get(url, auth=HTTPDigestAuth(user, password), timeout=3)
        print(f"Digest Auth -> Status: {r.status_code}")
        if r.status_code == 200:
            print("SUCCESS with Digest Auth!")
            break
            
    except Exception as e:
        print(f"Failed to connect: {e}")
