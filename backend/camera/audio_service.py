import os
import subprocess
import threading
import tempfile
import time
from urllib.parse import urlparse
import abc
import camera.constants.audio_constants as audio_const
from camera.audio_worker import audio_process_manager
class CameraAudioProvider(abc.ABC):
    @abc.abstractmethod
    def push_audio(self, camera_url: str, wav_file: str) -> bool:
        """Attempt to push a WAV file to the camera. Returns True on success, False on failure."""
        pass

class HikvisionAudioProvider(CameraAudioProvider):
    def push_audio(self, camera_url: str, wav_file: str) -> bool:
        print("[HikvisionAudio] Attempting ISAPI two-way audio push...")
        # TODO: Implement ISAPI PUT to /ISAPI/System/TwoWayAudio/channels/1/audioData
        # Requires HTTP Digest Auth and chunked transfer.
        return False

class CPPlusAudioProvider(CameraAudioProvider):
    def push_audio(self, camera_url: str, wav_file: str) -> bool:
        print("[CPPlusAudio] Attempting Dahua CGI / ONVIF Backchannel push...")
        # CP Plus / Dahua usually supports standard RTSP ANNOUNCE or CGI audio.cgi
        parsed = urlparse(camera_url)
        backchannel_url = f"{parsed.scheme}://{parsed.netloc}/cam/realmonitor?channel=1&subtype=0&unicast=true&proto=Onvif"
        
        try:
            result = subprocess.run(
                ["ffmpeg", "-re", "-i", wav_file, "-vn", "-ar", audio_const.ONVIF_AUDIO_SAMPLE_RATE, "-ac", audio_const.ONVIF_AUDIO_CHANNELS, "-acodec", audio_const.ONVIF_AUDIO_CODEC, "-f", "rtsp", backchannel_url],
                capture_output=True, text=True, timeout=audio_const.FFMPEG_TIMEOUT_SEC
            )
            return result.returncode == 0
        except Exception:
            return False

class TapoAudioProvider(CameraAudioProvider):
    def push_audio(self, camera_url: str, wav_file: str) -> bool:
        # Per user request: The system will speak locally, and the camera will just play its hardware siren.
        # Returning False forces the AudioService to immediately fall back to the local Mac speaker.
        print("[TapoAudio] Pushing audio to camera disabled. Falling back to local system speaker.")
        return False

class GenericONVIFAudioProvider(CameraAudioProvider):
    def push_audio(self, camera_url: str, wav_file: str) -> bool:
        print("[GenericONVIF] Attempting standard RTSP Backchannel push...")
        parsed = urlparse(camera_url)
        backchannel_url = f"{parsed.scheme}://{parsed.netloc}/backchannel"
        try:
            result = subprocess.run(
                ["ffmpeg", "-re", "-i", wav_file, "-vn", "-ar", audio_const.ONVIF_AUDIO_SAMPLE_RATE, "-ac", audio_const.ONVIF_AUDIO_CHANNELS, "-acodec", audio_const.ONVIF_AUDIO_CODEC, "-f", "rtsp", backchannel_url],
                capture_output=True, text=True, timeout=audio_const.FFMPEG_TIMEOUT_SEC
            )
            return result.returncode == 0
        except Exception:
            return False

class AudioService:
    def __init__(self):
        # We can map vendors if known. Default to Generic ONVIF.
        self.providers = {
            "hikvision": HikvisionAudioProvider(),
            "cpplus": CPPlusAudioProvider(),
            "tapo": TapoAudioProvider(),
            "generic": GenericONVIFAudioProvider()
        }
        self._disabled_urls = set()
        self.tts_voice = audio_const.DEFAULT_TTS_VOICE
        self.audio_cache = {}

    def speak(self, camera_url: str, text: str, vendor: str = "generic"):
        # Verification sessions identify a camera by ID, not a hardware URL.
        # In that case speak through the local system speaker immediately.
        if not camera_url:
            if text in self.audio_cache:
                wav_bytes = self.audio_cache[text]
                threading.Thread(
                    target=self._local_fallback,
                    args=(text, wav_bytes),
                    daemon=True,
                ).start()
            else:
                audio_process_manager.generate_async(
                    text,
                    lambda wav_bytes, txt: self._local_fallback(txt, wav_bytes),
                )
            return

        if text in self.audio_cache:
            wav_bytes = self.audio_cache[text]
            threading.Thread(target=self._on_audio_generated, args=(camera_url, text, vendor, wav_bytes), daemon=True).start()
        else:
            audio_process_manager.generate_async(text, lambda wav_bytes, txt: self._on_audio_generated(camera_url, txt, vendor, wav_bytes))

    def _on_audio_generated(self, camera_url: str, text: str, vendor: str, wav_bytes: bytes):
        if not wav_bytes:
            print(f"[AudioService] Failed to generate audio for: {text}")
            import sys
            import subprocess
            if sys.platform == "darwin":
                print(f"[AudioService] Using macOS native 'say' fallback.")
                subprocess.run(["say", text])
            return
            
        if text not in self.audio_cache:
            self.audio_cache[text] = wav_bytes

        if camera_url in self._disabled_urls:
            self._local_fallback(text, wav_bytes)
            return

        try:
            wav_path = tempfile.mktemp(suffix=".wav")
            with open(wav_path, "wb") as f:
                f.write(wav_bytes)
                
            provider = self.providers.get(vendor.lower(), self.providers["generic"])
            success = provider.push_audio(camera_url, wav_path)
            
            try:
                os.remove(wav_path)
            except:
                pass

            if not success:
                print(f"[AudioService] {vendor} provider failed. Disabling direct audio for this URL and falling back.")
                self._disabled_urls.add(camera_url)
                self._local_fallback(text, wav_bytes)

        except Exception as e:
            print(f"[AudioService] Error generating offline TTS: {e}")
            self._local_fallback(text, wav_bytes)

    def _local_fallback(self, text: str, wav_bytes: bytes):
        print(f"[AudioService] Local Speaker Fallback: {text}")
        try:
            if not wav_bytes:
                import sys
                if sys.platform == "darwin":
                    subprocess.run(["say", text])
                return

            wav_path = tempfile.mktemp(suffix=".wav")
            with open(wav_path, "wb") as f:
                f.write(wav_bytes)
            
            import sys
            if sys.platform == "darwin":
                subprocess.run(["afplay", wav_path])
            else:
                subprocess.run(["ffplay", "-nodisp", "-autoexit", wav_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                
            try:
                os.remove(wav_path)
            except:
                pass
        except Exception as e:
            print(f"[AudioService] Local fallback failed: {e}")

audio_service = AudioService()
