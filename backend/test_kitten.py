from kittentts import KittenTTS
import soundfile as sf
import time

print("Initializing model...")
t0 = time.time()
model = KittenTTS("KittenML/kitten-tts-nano-0.8")
print(f"Loaded in {time.time()-t0:.2f}s")

text = "Warning, unauthorized person detected. Please identify yourself."
print("Generating audio...")
t0 = time.time()
audio = model.generate(text, voice="Bruno")
print(f"Generated in {time.time()-t0:.2f}s")

sf.write('test_kitten.wav', audio, 24000)
print("Saved to test_kitten.wav")
