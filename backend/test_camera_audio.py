import argparse
import sys
from camera.audio_service import audio_service

def test_audio(camera_url: str, vendor: str, text: str):
    print(f"=========================================")
    print(f"Testing Two-Way Audio Strategy: {vendor.upper()}")
    print(f"Target Camera: {camera_url}")
    print(f"Text to Speak: '{text}'")
    print(f"=========================================\n")
    
    # We call _speak_sync directly so it blocks and we can see the output immediately
    audio_service._speak_sync(camera_url, text, vendor)
    
    print("\n[Test Complete]")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Test Camera Audio Pushing Strategies")
    parser.add_argument("--url", required=True, help="RTSP or HTTP URL of the camera (e.g. rtsp://user:pass@192.168.1.27:554/stream1)")
    parser.add_argument("--vendor", required=True, choices=["tapo", "hikvision", "cpplus", "generic"], help="The manufacturer strategy to use")
    parser.add_argument("--text", default="Testing one two three. Can you hear me?", help="The text to speak through the camera")

    args = parser.parse_args()
    
    try:
        test_audio(args.url, args.vendor, args.text)
    except KeyboardInterrupt:
        print("\nTest aborted.")
        sys.exit(0)
