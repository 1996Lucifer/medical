import threading
import pyttsx3
import tempfile
import time

def run_tts():
    print("Running in thread...")
    try:
        engine = pyttsx3.init()
        temp_wav = tempfile.mktemp(suffix=".aiff")
        print("Saving to file...")
        engine.save_to_file("Hello this is a test from thread", temp_wav)
        engine.runAndWait()
        print("Done!")
    except Exception as e:
        print("Exception:", e)

threading.Thread(target=run_tts).start()
time.sleep(2)
print("Main thread exiting")
