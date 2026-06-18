import cv2
import numpy as np
import onnxruntime as ort
from insightface.app import FaceAnalysis


def detect_compute_backend() -> dict:
    """
    Detect the best available compute backend and return
    quality settings tuned for that backend.
    """
    providers = ort.get_available_providers()

    if "CUDAExecutionProvider" in providers:
        return {
            "backend": "cuda",
            "ctx_id": 0,
            "det_size": (640, 640),   # Full detection resolution on GPU
            "frame_width": 1280,      # Process at 720p
            "jpeg_quality": 85,
            "target_fps": 25,
            "label": "CUDA GPU",
        }
    elif "CoreMLExecutionProvider" in providers:
        # Apple Silicon — fast Neural Engine
        return {
            "backend": "coreml",
            "ctx_id": 0,
            "det_size": (640, 640),
            "frame_width": 1280,
            "jpeg_quality": 82,
            "target_fps": 20,
            "label": "Apple CoreML",
        }
    else:
        # CPU only — use smaller detection grid and lower resolution
        return {
            "backend": "cpu",
            "ctx_id": -1,
            "det_size": (320, 320),   # Smaller = much faster on CPU
            "frame_width": 640,       # Process at 480p
            "jpeg_quality": 75,
            "target_fps": 10,
            "label": "CPU",
        }


try:
    from ultralytics import YOLO
except ImportError:
    YOLO = None

class VisionService:
    def __init__(self):
        self.config = detect_compute_backend()
        print(f"[VisionService] Using backend: {self.config['label']}")
        print(f"  det_size={self.config['det_size']}  "
              f"frame_width={self.config['frame_width']}  "
              f"fps={self.config['target_fps']}")

        self.app = FaceAnalysis(name="buffalo_l", root="~/.insightface")
        self.app.prepare(
            ctx_id=self.config["ctx_id"],
            det_size=self.config["det_size"],
        )
        
        if YOLO:
            print("[VisionService] Loading YOLOv8n for equipment tracking...")
            self.yolo_model = YOLO("yolov8n.pt")
        else:
            self.yolo_model = None

    # ── Properties consumed by routes.py ─────────────────────────────────────

    @property
    def frame_width(self) -> int:
        return self.config["frame_width"]

    @property
    def jpeg_quality(self) -> int:
        return self.config["jpeg_quality"]

    @property
    def target_fps(self) -> int:
        return self.config["target_fps"]

    @property
    def backend_label(self) -> str:
        return self.config["label"]

    # ── Core methods ──────────────────────────────────────────────────────────

    def extract_embedding(self, image_path: str):
        """
        Reads an image from disk and extracts the 512D face embedding.
        Returns the embedding as a numpy array, or None if no face found.
        """
        img = cv2.imread(image_path)
        if img is None:
            return None
        faces = self.app.get(img)
        if not faces:
            return None
        return faces[0].embedding

    def cosine_similarity(self, embedding1, embedding2):
        dot = np.dot(embedding1, embedding2)
        n1 = np.linalg.norm(embedding1)
        n2 = np.linalg.norm(embedding2)
        return dot / (n1 * n2) if (n1 and n2) else 0.0

    def process_frame(self, frame, db_staff_list):
        """
        Detect faces, match against staff DB, draw bounding boxes.
        Detect equipment using YOLO.
        Returns:
            (processed_frame, face_events, equipment_events)
        """
        faces = self.app.get(frame)
        face_events = []

        for face in faces:
            bbox = face.bbox.astype(int)
            emb = face.embedding

            best_match = "Unknown"
            best_score = 0.0

            for staff in db_staff_list:
                db_emb = np.array(staff["embedding"])
                score = self.cosine_similarity(emb, db_emb)
                if score > best_score:
                    best_score = score
                    best_match = staff["name"]

            if best_score < 0.3:
                best_match = "Unknown"
            else:
                face_events.append({"name": best_match, "score": float(best_score)})

            color = (0, 255, 0) if best_match != "Unknown" else (0, 0, 255)
            cv2.rectangle(frame, (bbox[0], bbox[1]), (bbox[2], bbox[3]), color, 2)

            if best_match != "Unknown":
                label = f"{best_match}  {best_score:.0%}"
            else:
                label = "Unknown"

            label_size, _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.7, 2)
            lx, ly = bbox[0], bbox[1] - 10
            cv2.rectangle(frame,
                          (lx, ly - label_size[1] - 4),
                          (lx + label_size[0] + 4, ly + 4),
                          color, cv2.FILLED)
            cv2.putText(frame, label, (lx + 2, ly),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)

        equipment_events = []
        if self.yolo_model:
            results = self.yolo_model.track(frame, persist=True, verbose=False)
            if results and results[0].boxes:
                boxes = results[0].boxes
                for box in boxes:
                    cls_id = int(box.cls[0])
                    # 56: chair -> Wheelchair, 59: bed -> Hospital Bed
                    if cls_id in [56, 59]:
                        conf = float(box.conf[0])
                        track_id = int(box.id[0]) if box.id is not None else -1
                        label_map = {56: "Wheelchair", 59: "Hospital Bed"}
                        equip_class = label_map.get(cls_id, "Equipment")
                        
                        equipment_events.append({
                            "class": equip_class,
                            "track_id": track_id,
                            "score": conf
                        })
                        
                        x1, y1, x2, y2 = map(int, box.xyxy[0])
                        cv2.rectangle(frame, (x1, y1), (x2, y2), (255, 165, 0), 2)
                        
                        label = f"{equip_class} #{track_id}"
                        cv2.putText(frame, label, (x1, y1 - 10),
                                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 165, 0), 2)

        return frame, face_events, equipment_events



# Singleton instance — initialised once at startup
vision_service = VisionService()
