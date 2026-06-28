import cv2
import numpy as np

class ComplianceService:
    """
    Modular service for running secondary compliance and safety checks
    on regions of interest detected by the primary vision service.
    """
    
    def __init__(self):
        # In a full deployment, this is where you'd load a YOLOv8 
        # or custom classification ONNX model specifically trained for PPE.
        self._model_loaded = False

    def detect_ppe(self, frame: np.ndarray, face_bbox: tuple) -> dict:
        """
        Evaluates the face bounding box to determine if the person is wearing a mask.
        
        Args:
            frame: The full camera frame (BGR)
            face_bbox: Tuple (x1, y1, x2, y2)
            
        Returns:
            dict containing compliance flags, e.g. {"has_mask": bool, "confidence": float}
        """
        x1, y1, x2, y2 = [int(v) for v in face_bbox]
        
        # Ensure bounds are within frame
        h, w = frame.shape[:2]
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(w, x2), min(h, y2)
        
        if y2 <= y1 or x2 <= x1:
            return {"has_mask": False, "confidence": 0.0}
            
        # Extract face ROI
        face_roi = frame[y1:y2, x1:x2]
        
        # --- MODULAR PLACEHOLDER HEURISTIC ---
        # A real implementation would run face_roi through a classifier here.
        # As a fallback heuristic without downloading heavy weights: 
        # We can analyze the lower half of the face for typical mask colors (blue/white).
        
        roi_h, roi_w = face_roi.shape[:2]
        lower_half = face_roi[roi_h//2:, :]
        
        if lower_half.size == 0:
            return {"has_mask": False, "confidence": 0.0}
            
        # Convert to HSV to check for blue/cyan (common surgical mask) or just high brightness (white mask)
        hsv = cv2.cvtColor(lower_half, cv2.COLOR_BGR2HSV)
        
        # Blue/Cyan range
        lower_blue = np.array([80, 50, 50])
        upper_blue = np.array([130, 255, 255])
        blue_mask = cv2.inRange(hsv, lower_blue, upper_blue)
        
        # White range (low saturation, high value)
        lower_white = np.array([0, 0, 200])
        upper_white = np.array([180, 30, 255])
        white_mask = cv2.inRange(hsv, lower_white, upper_white)
        
        combined_mask = cv2.bitwise_or(blue_mask, white_mask)
        mask_ratio = cv2.countNonZero(combined_mask) / (lower_half.shape[0] * lower_half.shape[1] + 1e-6)
        
        # If >30% of the lower face matches mask colors, we assume a mask is present
        has_mask = mask_ratio > 0.30
        confidence = min(mask_ratio * 2.0, 0.99) if has_mask else max(1.0 - (mask_ratio * 2.0), 0.5)
        
        return {
            "has_mask": bool(has_mask),
            "confidence": float(confidence)
        }

# Global singleton for compliance
compliance_service = ComplianceService()
