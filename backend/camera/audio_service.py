import os
import subprocess
import threading
import tempfile
import time
from urllib.parse import urlparse
import abc

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
                ["ffmpeg", "-re", "-i", wav_file, "-vn", "-acodec", "copy", "-f", "rtsp", backchannel_url],
                capture_output=True, text=True, timeout=10
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
                ["ffmpeg", "-re", "-i", wav_file, "-vn", "-acodec", "copy", "-f", "rtsp", backchannel_url],
                capture_output=True, text=True, timeout=5
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

    def speak(self, camera_url: str, text: str, vendor: str = "generic"):
        threading.Thread(target=self._speak_sync, args=(camera_url, text, vendor), daemon=True).start()

    def _speak_sync(self, camera_url: str, text: str, vendor: str):
        if camera_url in self._disabled_urls:
            self._local_fallback(text)
            return

        try:
            print(f"[AudioService] Generating TTS for {vendor} camera: {text}")
            
            temp_aiff = tempfile.mktemp(suffix=".aiff")
            temp_wav = tempfile.mktemp(suffix=".wav")
            os.system(f'say -o "{temp_aiff}" "{text}"')
            
            # Convert to 8000Hz PCM
            subprocess.run(
                ["ffmpeg", "-y", "-i", temp_aiff, "-ar", "8000", "-ac", "1", "-acodec", "pcm_mulaw", temp_wav],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True
            )

            provider = self.providers.get(vendor.lower(), self.providers["generic"])
            success = provider.push_audio(camera_url, temp_wav)

            if not success:
                print(f"[AudioService] {vendor} provider failed. Disabling direct audio for this URL and falling back.")
                self._disabled_urls.add(camera_url)
                self._local_fallback(text)
            else:
                print(f"[AudioService] Successfully played audio on {vendor} camera speaker.")

        except Exception as e:
            print(f"[AudioService] Error: {e}")
            self._local_fallback(text)
        finally:
            if 'temp_aiff' in locals() and os.path.exists(temp_aiff):
                os.remove(temp_aiff)
            if 'temp_wav' in locals() and os.path.exists(temp_wav):
                os.remove(temp_wav)

    def _local_fallback(self, text: str):
        print(f"[AudioService] Local Speaker Fallback: {text}")
        os.system(f'say "{text}"')

audio_service = AudioService()
