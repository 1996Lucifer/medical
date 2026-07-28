"""
drawing_constants.py
This file contains all the constants used for drawing visual elements 
(like bounding boxes, text, and overlays) on the camera frames.
By centralizing these settings, we ensure consistent styling across 
different visual components and make it easier to theme or adjust the UI.
"""

import cv2

# ==========================================
# Color Definitions (BGR Format for OpenCV)
# ==========================================

# Standard Colors
COLOR_WHITE = (255, 255, 255)       # Used for standard text (e.g., Titles)
COLOR_DARK_GREY = (40, 40, 40)      # Used for background panels (glassmorphism)
COLOR_YELLOW = (0, 255, 255)        # Used for confidence scores and tracing arrows
COLOR_CYAN = (255, 255, 0)          # Used for skeletons and alternate highlights

# Status Colors
COLOR_UNAUTHORIZED = (0, 0, 255)    # Red: Used for unauthorized persons, restricted violations, or missing PPE
COLOR_VERIFIED = (0, 255, 0)        # Green: Used for verified staff and complete PPE compliance
COLOR_WARNING = (0, 165, 255)       # Orange: Used for warnings like partial PPE or observation zones

# ==========================================
# Bounding Box Settings
# ==========================================

BBOX_CORNER_THICKNESS = 3           # Thickness of the corners drawn around a detected person
BBOX_CORNER_LENGTH = 20             # Length of the corner segments extending from the edges
BBOX_FAINT_THICKNESS = 2            # Thickness of the faintly drawn full rectangle connecting the corners
BBOX_FAINT_OPACITY = 0.5            # Opacity of the faint bounding box (used in cv2.addWeighted)

# ==========================================
# Typography Settings
# ==========================================

FONT_STYLE = cv2.FONT_HERSHEY_SIMPLEX # Standard font used for all UI text overlays

# Main Title Text (e.g., Staff Name & ID)
FONT_SCALE_TITLE = 0.6
FONT_THICKNESS_TITLE = 1

# Subtitle Text (e.g., Confidence, Status)
FONT_SCALE_SUBTITLE = 0.45
FONT_THICKNESS_SUBTITLE = 1

# Incident Events Text (e.g., FALL DETECTED)
FONT_SCALE_INCIDENT = 0.8
FONT_THICKNESS_INCIDENT = 1

# ==========================================
# UI Panel Settings
# ==========================================

PANEL_PADDING = 5                   # Padding around text inside the glassmorphism panel
PANEL_MARGIN_BOTTOM = 10            # Margin between the bounding box and the panel
PANEL_OPACITY_BG = 0.7              # Opacity of the dark grey background panel
PANEL_OPACITY_FG = 0.3              # Opacity of the foreground frame for the panel
