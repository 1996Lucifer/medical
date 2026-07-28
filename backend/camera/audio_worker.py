import multiprocessing as mp
import threading
import traceback
import tempfile
import os

def _audio_worker_process(input_queue, output_queue):
    """
    Dedicated process for heavy TTS generation.
    Initializes KittenTTS in this process memory.
    """
    print("[AudioWorkerProcess] Initializing TTS Model in separate process...")
    try:
        from camera.model_manager import ModelManager
        tts = ModelManager().get_tts_model()
        if not tts:
            output_queue.put({"type": "fatal", "error": "TTS Model failed to load."})
            return
    except Exception as e:
        print(f"[AudioWorkerProcess] Failed to initialize TTS: {e}")
        output_queue.put({"type": "fatal", "error": str(e)})
        return
        
    while True:
        try:
            req = input_queue.get()
            if req is None:
                break
                
            if req["type"] == "generate":
                text = req["text"]
                req_id = req["req_id"]
                
                import camera.constants.audio_constants as audio_const
                audio_np = tts.generate(text, speed=audio_const.DEFAULT_TTS_SPEED)
                
                import io
                import soundfile as sf
                mem_file = io.BytesIO()
                sf.write(mem_file, audio_np, audio_const.KITTEN_TTS_SAMPLE_RATE, format='WAV', subtype='PCM_16')
                audio_bytes = mem_file.getvalue()
                
                output_queue.put({
                    "type": "result",
                    "req_id": req_id,
                    "audio_bytes": audio_bytes,
                    "text": text
                })
        except Exception as e:
            traceback.print_exc()
            output_queue.put({"type": "error", "error": str(e)})

class AudioProcessManager:
    _instance = None
    _thread_lock = threading.Lock()
    
    def __new__(cls, *args, **kwargs):
        with cls._thread_lock:
            if cls._instance is None:
                cls._instance = super(AudioProcessManager, cls).__new__(cls)
                cls._instance._init_manager(*args, **kwargs)
            return cls._instance

    def _init_manager(self):
        self.input_queue = None
        self.output_queue = None
        self.process = None
        self.callbacks = {} # req_id -> callback function
        self.req_counter = 0
        self.lock = threading.Lock()
        
    def start_process(self):
        if self.process is not None:
            return
            
        ctx = mp.get_context('spawn')
        self.input_queue = ctx.Queue()
        self.output_queue = ctx.Queue()
        
        self.process = ctx.Process(
            target=_audio_worker_process,
            args=(self.input_queue, self.output_queue),
            daemon=True
        )
        self.process.start()
        
        self.reader_thread = threading.Thread(target=self._read_results, daemon=True)
        self.reader_thread.start()

    def _read_results(self):
        while True:
            try:
                res = self.output_queue.get()
                if res.get("type") == "result":
                    req_id = res["req_id"]
                    cb = None
                    with self.lock:
                        if req_id in self.callbacks:
                            cb = self.callbacks.pop(req_id)
                    if cb:
                        try:
                            cb(res["audio_bytes"], res["text"])
                        except Exception as e:
                            print(f"[AudioProcessManager] Callback error: {e}")
            except Exception as e:
                pass

    def generate_async(self, text, callback=None):
        if not self.input_queue:
            if callback: callback(None, text)
            return
            
        with self.lock:
            self.req_counter += 1
            req_id = self.req_counter
            if callback:
                self.callbacks[req_id] = callback
                
        self.input_queue.put({
            "type": "generate",
            "req_id": req_id,
            "text": text
        })

audio_process_manager = AudioProcessManager()
