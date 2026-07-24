import sys, time
from camera.audio_service import audio_service

print("Testing audio_service with local fallback (camera_url='0')...")
audio_service.speak("0", "Warning, this is a test of the audio system.")

# Wait a few seconds for the background process and afplay to finish
time.sleep(5)
print("Test complete.")
