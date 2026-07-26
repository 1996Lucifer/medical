import os
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

        self._mp_holistic = None
        self._mp_lock = threading.Lock()

        self._mp_face_mesh = None
        self._mp_face_mesh_lock = threading.Lock()

        self._mp_hands = None
        self._mp_hands_lock = threading.Lock()

        self._yolo_detectors = {}
        self._yolo_lock = threading.Lock()

        self._ppe_detector = None
        self._ppe_lock = threading.Lock()

        self._yolo_world_detector = None
        self._yolo_world_lock = threading.Lock()

        self._tts_model = None
        self._tts_lock = threading.Lock()

    def get_face_analysis(self, config=None):
        if self._face_app is None:
            with self._face_lock:
                if self._face_app is None:
                    print("[ModelManager] Lazy loading InsightFace (buffalo_l)...")
                    from insightface.app import FaceAnalysis
                    providers = ["CPUExecutionProvider"]
                    try:
                        import onnxruntime as ort
                        available = ort.get_available_providers()
                        preferred = [
                            "CUDAExecutionProvider",
                            "OpenVINOExecutionProvider",
                            "CPUExecutionProvider",
                        ]
                        providers = [p for p in preferred if p in available] or providers
                    except Exception:
                        pass
                    self._face_app = FaceAnalysis(
                        name="buffalo_l",
                        root="~/.insightface",
                        providers=providers,
                    )
                    if config:
                        self._face_app.prepare(
                            ctx_id=config["ctx_id"],
                            det_size=config["det_size"],
                        )
        return self._face_app

    def get_mp_holistic(self):
        if self._mp_holistic is None:
            with self._mp_lock:
                if self._mp_holistic is None:
                    print("[ModelManager] Lazy loading MediaPipe Holistic...")
                    try:
                        from mediapipe.tasks import python
                        from mediapipe.tasks.python import vision
                        model_path = os.path.join(os.path.dirname(__file__), "..", "models", "holistic_landmarker.task")
                        base_options = python.BaseOptions(model_asset_path=model_path)
                        options = vision.HolisticLandmarkerOptions(base_options=base_options)
                        self._mp_holistic = vision.HolisticLandmarker.create_from_options(options)
                    except ImportError:
                        print("[ModelManager] Failed to load MediaPipe (mediapipe not installed)")
                        self._mp_holistic = False
        return self._mp_holistic if self._mp_holistic is not False else None

    def get_mp_face_mesh(self):
        """
        Disabled. MediaPipe Python API 0.10.x removed solutions.
        vision_service_zones.py will seamlessly use geometric face cropping.
        """
        return None

    def get_mp_hands(self):
        """
        Disabled. MediaPipe Python API 0.10.x removed solutions.
        vision_service_zones.py will seamlessly use geometric hand cropping.
        """
        return None

    def get_yolo_detector(self, camera_id="default"):
        """
        Load YOLO detector for multi-person detection and ByteTrack tracking.
        Prefers the OpenVINO model (which includes person detection) to avoid ONNX CPU fallback.
        Creates a distinct YOLO instance per camera_id so internal ByteTrack tracker state is isolated.
        """
        if camera_id not in self._yolo_detectors:
            with self._yolo_lock:
                if camera_id not in self._yolo_detectors:
                    print(f"[ModelManager] Lazy loading YOLO11n for camera {camera_id}...")
                    try:
                        from ultralytics import YOLO
                        from camera.vision_constants import YOLO_MODEL
                        models_dir = os.path.abspath(
                            os.path.join(os.path.dirname(__file__), "..", "models")
                        )
                        onnx_path = os.path.join(models_dir, YOLO_MODEL)

                        if os.path.exists(onnx_path):
                            self._yolo_detectors[camera_id] = YOLO(onnx_path)
                        else:
                            print(f"[ModelManager] {YOLO_MODEL} not found in models/. Downloading...")
                            self._yolo_detectors[camera_id] = YOLO(YOLO_MODEL)
                        try:
                            self._yolo_detectors[camera_id].fuse()
                        except Exception:
                            pass
                        print(f"[ModelManager] YOLO11n loaded successfully for camera {camera_id}.")
                    except ImportError:
                        print("[ModelManager] Failed to load YOLO (ultralytics not installed)")
                        self._yolo_detectors[camera_id] = False
                    except Exception as e:
                        print(f"[ModelManager] Failed to load YOLO for camera {camera_id}: {e}")
                        self._yolo_detectors[camera_id] = False

        model = self._yolo_detectors.get(camera_id)
        return model if model is not False else None

    def get_ppe_detector(self):
        """Load the lightweight detector trained for masks and gloves (prefer OpenVINO on CPU)."""
        if self._ppe_detector is None:
            with self._ppe_lock:
                if self._ppe_detector is None:
                    try:
                        from ultralytics import YOLO
                        from camera.vision_constants import (
                            PPE_YOLO_MODEL,
                            PPE_YOLO_OPENVINO_DIR,
                        )

                        models_dir = os.path.abspath(
                            os.path.join(os.path.dirname(__file__), "..", "models")
                        )
                        target_ov = os.path.join(models_dir, "best_openvino_model")
                        onnx_path = os.path.join(models_dir, PPE_YOLO_MODEL)

                        # Prefer OpenVINO model for real-time CPU performance if available
                        if os.path.exists(target_ov):
                            print(
                                f"[ModelManager] Loading OpenVINO PPE YOLO model from {target_ov}..."
                            )
                            try:
                                self._ppe_detector = YOLO(target_ov, task="detect")
                                print(
                                    "[ModelManager] OpenVINO PPE YOLO model loaded successfully."
                                )
                            except Exception as ov_err:
                                print(
                                    f"[ModelManager] OpenVINO load failed ({ov_err}), falling back to ONNX ({onnx_path})..."
                                )
                                self._ppe_detector = YOLO(onnx_path)
                        else:
                            print(
                                f"[ModelManager] Loading ONNX PPE YOLO model from {onnx_path}..."
                            )
                            self._ppe_detector = YOLO(onnx_path)

                        try:
                            self._ppe_detector.fuse()
                        except Exception:
                            pass
                    except Exception as exc:
                        print(f"[ModelManager] Failed to load PPE YOLO: {exc}")
                        self._ppe_detector = False
        return self._ppe_detector if self._ppe_detector is not False else None

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

    def get_yolo_world_detector(self):
        """Load YOLO-World v2 detector for open-vocabulary detection from models directory."""
        if self._yolo_world_detector is None:
            with self._yolo_world_lock:
                if self._yolo_world_detector is None:
                    try:
                        from ultralytics import YOLO
                        models_dir = os.path.abspath(
                            os.path.join(os.path.dirname(__file__), "..", "models")
                        )
                        world_onnx = os.path.join(models_dir, "yolov8s-worldv2.onnx")
                        if os.path.exists(world_onnx):
                            print(f"[ModelManager] Loading YOLO-World v2 model from {world_onnx}...")
                            self._yolo_world_detector = YOLO(world_onnx)
                        else:
                            print("[ModelManager] Loading default YOLOv8s-World v2 model...")
                            self._yolo_world_detector = YOLO("yolov8s-worldv2.onnx")
                        print("[ModelManager] YOLO-World v2 model loaded successfully.")
                    except Exception as exc:
                        print(f"[ModelManager] Failed to load YOLO-World v2: {exc}")
                        self._yolo_world_detector = False
        return self._yolo_world_detector if self._yolo_world_detector is not False else None

