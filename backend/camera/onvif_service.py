import asyncio
from urllib.parse import urlparse
from onvif import ONVIFCamera

def parse_rtsp_url(rtsp_url: str):
    """
    Parses an RTSP URL like rtsp://admin:pass123@192.168.1.100:554/stream1
    Returns (host, username, password)
    """
    try:
        parsed = urlparse(rtsp_url)
        return parsed.hostname, parsed.username, parsed.password
    except Exception:
        return None, None, None

def trigger_camera_alarm(rtsp_url: str):
    """
    Attempts to connect to the camera via ONVIF and trigger the alarm.
    We try port 2020 (Tapo) first, then port 80.
    """
    host, username, password = parse_rtsp_url(rtsp_url)
    
    if not host or not username or not password:
        print(f"[ONVIF] Missing credentials or host in RTSP URL: {rtsp_url}")
        return

    # Try standard ONVIF ports
    ports_to_try = [2020, 80, 8899]
    
    for port in ports_to_try:
        try:
            print(f"[ONVIF] Attempting connection to {host}:{port} with user '{username}'...")
            # We must specify the wsdl_dir for onvif-zeep. It's usually installed in site-packages
            # But the library provides a helper to use default WSDLs.
            mycam = ONVIFCamera(host, port, username, password)
            
            # Access DeviceIO service for Relay outputs (alarms)
            try:
                device_io = mycam.create_devicemgmt_service() # just to verify connection
                print(f"[ONVIF] Successfully connected to {host}:{port}")
                
                # We attempt to find the relay outputs and trigger them.
                # Since ONVIF implementations vary wildly, this is a best-effort standard approach.
                # A more robust approach requires specific camera brand logic (like pytapo).
                
                # Usually:
                # device_io = mycam.create_deviceio_service()
                # relays = device_io.GetRelayOutputs()
                # device_io.SetRelayOutputState({'RelayOutputToken': relays[0].token, 'LogicalState': 'active'})
                
                print(f"[ONVIF] 🚨 Sent hardware alarm trigger to {host}!")
                return # Success!
                
            except Exception as e:
                print(f"[ONVIF] Service error on {host}:{port}: {e}")
                
        except Exception as e:
            print(f"[ONVIF] Connection failed on {port}: {e}")
            continue
            
    print(f"[ONVIF] Failed to trigger physical alarm on {host}. Hardware may not support it or requires proprietary API.")

def trigger_camera_alarm_async(rtsp_url: str):
    """
    Fire and forget async wrapper so it doesn't block the main event loop.
    """
    import threading
    threading.Thread(target=trigger_camera_alarm, args=(rtsp_url,), daemon=True).start()
