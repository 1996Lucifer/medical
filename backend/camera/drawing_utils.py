import cv2

SKELETON_EDGES = [
    (0, 1), (0, 2), (1, 3), (2, 4),                     # Face
    (5, 6), (5, 7), (7, 9), (6, 8), (8, 10),            # Arms & Shoulders
    (11, 12), (5, 11), (6, 12),                         # Torso
    (11, 13), (13, 15), (12, 14), (14, 16)              # Legs
]

def draw_skeleton(image, kps, kps_conf, conf_threshold=0.4):
    """
    Draws the COCO 17-keypoint skeleton on the image.
    :param image: The image frame (mutated in-place).
    :param kps: List of 17 (x, y) coordinates.
    :param kps_conf: List of 17 confidence values.
    :param conf_threshold: Minimum confidence to draw a point or line.
    """
    if not kps or not kps_conf or len(kps) < 17 or len(kps_conf) < 17:
        return

    # Draw lines (edges)
    for edge in SKELETON_EDGES:
        p1, p2 = edge
        if kps_conf[p1] > conf_threshold and kps_conf[p2] > conf_threshold:
            x1, y1 = int(kps[p1][0]), int(kps[p1][1])
            x2, y2 = int(kps[p2][0]), int(kps[p2][1])
            cv2.line(image, (x1, y1), (x2, y2), (255, 255, 0), 2)
            
    # Draw points (dots)
    for i in range(17):
        if kps_conf[i] > conf_threshold:
            kx, ky = int(kps[i][0]), int(kps[i][1])
            cv2.circle(image, (kx, ky), 5, (0, 255, 255), -1)
