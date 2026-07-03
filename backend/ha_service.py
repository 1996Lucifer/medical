import os
import requests
import threading

def get_ha_headers():
    token = os.getenv("HOME_ASSISTANT_TOKEN", "")
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }

def trigger_siren_sync(entity_id: str):
    if not entity_id:
        return

    ha_url = os.getenv("HOME_ASSISTANT_URL", "http://localhost:8123").rstrip("/")
    token = os.getenv("HOME_ASSISTANT_TOKEN", "")
    
    if not token:
        print("[HA] Warning: HOME_ASSISTANT_TOKEN not set. Cannot trigger siren.")
        return
        
    url = f"{ha_url}/api/services/siren/turn_on"
    payload = {"entity_id": entity_id}
    
    try:
        resp = requests.post(url, headers=get_ha_headers(), json=payload, timeout=5)
        resp.raise_for_status()
        print(f"[HA] 🚨 Siren successfully triggered for {entity_id}")
        
        # Optional: Turn it off after a few seconds
        import time
        time.sleep(5)
        off_url = f"{ha_url}/api/services/siren/turn_off"
        requests.post(off_url, headers=get_ha_headers(), json=payload, timeout=5)
        print(f"[HA] 🛑 Siren disabled for {entity_id}")
        
    except Exception as e:
        print(f"[HA] Failed to trigger siren for {entity_id}: {e}")

def trigger_siren(entity_id: str):
    """
    Fire and forget async wrapper for triggering Home Assistant sirens.
    """
    if not entity_id:
        return
    threading.Thread(target=trigger_siren_sync, args=(entity_id,), daemon=True).start()
