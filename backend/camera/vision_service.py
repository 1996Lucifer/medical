import cv2
import numpy as np
import onnxruntime as ort
from camera.model_manager import ModelManager

from camera.constants.vision_constants import get_runtime_vision_config


def detect_compute_backend() -> dict:
    """
    Detect the best available compute backend and return
    quality settings tuned for that backend.
    """
    return get_runtime_vision_config(ort.get_available_providers())


class VisionService:
    """
    Legacy single-camera service, superseded by the zone-based multi-camera
    pipeline in vision_service_zones.py for live recognition. What remains
    live here is the photo-enrollment path (extract_embedding/
    extract_upper_embedding), still used by routers/staff.py when a staff
    member's photo is registered - everything else this class used to do
    (process_frame, its own staff-embedding cache, PPE color detection) was
    dead code with zero callers once the zone-based pipeline took over and
    was removed (see /audit 2026-09-15).
    """

    def __init__(self):
        self.config = detect_compute_backend()
        print(f"[VisionService] Using backend: {self.config['label']}")
        print(f"  det_size={self.config['det_size']}  "
              f"frame_width={self.config['frame_width']}  "
              f"fps={self.config['target_fps']}")

    def extract_embedding(self, image_path: str):
        """
        Reads an image from disk and extracts the 512D face embedding.
        Returns the embedding as a numpy array, or None if no face found.
        """
        img = cv2.imread(image_path)
        if img is None:
            return None
        app = ModelManager().get_face_analysis(self.config)
        faces = app.get(img)
        if not faces:
            return None
        return faces[0].embedding

    def extract_upper_embedding(self, image_path: str = None, img: np.ndarray = None, bbox: list = None):
        """
        Mimics Apple's mask algorithm by cropping the upper 45% of the face
        (periocular region: eyes/eyebrows) and generating a dedicated 512D embedding.
        """
        if img is None and image_path:
            img = cv2.imread(image_path)
        if img is None:
            return None

        if bbox is None:
            app = ModelManager().get_face_analysis(self.config)
            faces = app.get(img)
            if not faces:
                return None
            bbox = faces[0].bbox.astype(int)

        # Crop the face bounding box
        x1, y1, x2, y2 = map(int, bbox)
        h, w, _ = img.shape
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(w, x2), min(h, y2)

        face_h = y2 - y1
        face_w = x2 - x1
        if face_h <= 0 or face_w <= 0:
            return None

        # Crop the upper 45% of the face
        upper_h = int(face_h * 0.45)
        upper_face_crop = img[y1 : y1 + upper_h, x1 : x2]

        if upper_face_crop.size == 0:
            return None

        # InsightFace's recognition model expects a 112x112 RGB image
        upper_face_resized = cv2.resize(upper_face_crop, (112, 112))
        upper_face_rgb = cv2.cvtColor(upper_face_resized, cv2.COLOR_BGR2RGB)

        # Directly pass the cropped unaligned upper face to the ArcFace recognition model
        app = ModelManager().get_face_analysis(self.config)
        embedding = app.models['recognition'].get_feat(upper_face_rgb)
        return embedding.flatten()


# Singleton instance — initialised once at startup
vision_service = VisionService()
