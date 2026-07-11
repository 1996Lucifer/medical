import pyttsx3
import tempfile
import os
import subprocess

try:
    print("Testing pyttsx3...")
    engine = pyttsx3.init()
    temp_wav = tempfile.mktemp(suffix=".aiff")
    print("Saving to file:", temp_wav)
    engine.save_to_file("Hello this is a test", temp_wav)
    engine.runAndWait()
    
    if os.path.exists(temp_wav):
        print(f"File created successfully: {os.path.getsize(temp_wav)} bytes")
        subprocess.run(["ffplay", "-nodisp", "-autoexit", temp_wav], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.remove(temp_wav)
    else:
        print("File was NOT created!")
except Exception as e:
    print("Error:", e)
