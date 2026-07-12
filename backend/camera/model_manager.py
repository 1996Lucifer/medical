import threading

class ModelManager:
    """
    Singleton Manager for all AI models.
    Loads models lazily only upon first request to improve startup time and save memory.
    """
    _instance = None
    _lock = threading.Lock()

    def __new__(cls):
        with cls._lock:
            if cls._instance is None:
                cls._instance = super(ModelManager, cls).__new__(cls)
                cls._instance._init_manager()
            return cls._instance

    def _init_manager(self):
        self._face_app = None
        self._face_lock = threading.Lock()
        
        self._yolo_equipment = None
        self._yolo_equipment_lock = threading.Lock()
        
        self._yolo_pose = None
        self._yolo_pose_lock = threading.Lock()
        
        self._yolo_ppe = None
        self._yolo_ppe_lock = threading.Lock()
        
        self._tts_model = None
        self._tts_lock = threading.Lock()

    def get_face_analysis(self, config=None):
        if self._face_app is None:
            with self._face_lock:
                if self._face_app is None:
                    print("[ModelManager] Lazy loading InsightFace (buffalo_l)...")
                    from insightface.app import FaceAnalysis
                    self._face_app = FaceAnalysis(name="buffalo_l", root="~/.insightface")
                    if config:
                        self._face_app.prepare(
                            ctx_id=config["ctx_id"],
                            det_size=config["det_size"],
                        )
        return self._face_app

    def get_yolo_equipment(self):
        if self._yolo_equipment is None:
            with self._yolo_equipment_lock:
                if self._yolo_equipment is None:
                    print("[ModelManager] Lazy loading YOLOv8n (Equipment)...")
                    try:
                        from ultralytics import YOLO
                        self._yolo_equipment = YOLO("models/yolov8n.onnx", task="detect")
                    except ImportError:
                        print("[ModelManager] Failed to load YOLOv8n (ultralytics not installed)")
                        self._yolo_equipment = False
        return self._yolo_equipment if self._yolo_equipment is not False else None

    def get_yolo_pose(self):
        if self._yolo_pose is None:
            with self._yolo_pose_lock:
                if self._yolo_pose is None:
                    print("[ModelManager] Lazy loading YOLOv8n-pose...")
                    try:
                        from ultralytics import YOLO
                        self._yolo_pose = YOLO("models/yolov8n-pose.onnx", task="pose")
                    except ImportError:
                        print("[ModelManager] Failed to load YOLOv8n-pose (ultralytics not installed)")
                        self._yolo_pose = False
        return self._yolo_pose if self._yolo_pose is not False else None

    def get_yolo_ppe(self):
        if self._yolo_ppe is None:
            with self._yolo_ppe_lock:
                if self._yolo_ppe is None:
                    print("[ModelManager] Lazy loading YOLOv8n-PPE (Nano)...")
                    try:
                        from ultralytics import YOLO
                        self._yolo_ppe = YOLO("models/yolov8n-ppe.onnx", task="detect")
                    except ImportError:
                        print("[ModelManager] Failed to load YOLOv8n-PPE (ultralytics not installed)")
                        self._yolo_ppe = False
        return self._yolo_ppe if self._yolo_ppe is not False else None

    def get_tts_model(self):
        if self._tts_model is None:
            with self._tts_lock:
                if self._tts_model is None:
                    print("[ModelManager] Lazy loading KittenTTS...")
                    try:
                        import camera.audio_constants as audio_const
                        from kittentts import KittenTTS
                        self._tts_model = KittenTTS(audio_const.KITTEN_TTS_MODEL)
                        print("[ModelManager] KittenTTS model loaded successfully.")
                    except Exception as e:
                        print(f"[ModelManager] Failed to load KittenTTS: {e}")
                        self._tts_model = False
        return self._tts_model if self._tts_model is not False else None
