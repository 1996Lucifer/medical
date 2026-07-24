from kittentts import KittenTTS
import camera.audio_constants as audio_const
import io, soundfile as sf
import os

tts = KittenTTS(audio_const.KITTEN_TTS_MODEL)
print("TTS loaded.")
audio_np = tts.generate("Warning, this is a test.", speed=audio_const.DEFAULT_TTS_SPEED)
print(f"Generated {len(audio_np)} samples.")
mem_file = io.BytesIO()
sf.write(mem_file, audio_np, audio_const.KITTEN_TTS_SAMPLE_RATE, format='WAV', subtype='PCM_16')
audio_bytes = mem_file.getvalue()
print(f"WAV size: {len(audio_bytes)} bytes.")

if len(audio_bytes) > 100:
    print("TTS working!")
else:
    print("TTS generated empty audio!")
