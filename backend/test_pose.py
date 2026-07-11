import cv2
import numpy as np
from insightface.app import FaceAnalysis

app = FaceAnalysis(name="buffalo_l", root="~/.insightface")
app.prepare(ctx_id=-1, det_size=(640, 640))
img = np.zeros((640, 640, 3), dtype=np.uint8)
# We can't guarantee a face in a black image, so let's just inspect the fields of a face object if possible, or just download a face.
import urllib.request
urllib.request.urlretrieve("https://raw.githubusercontent.com/deepinsight/insightface/master/python-package/insightface/data/images/t1.jpg", "t1.jpg")
img = cv2.imread("t1.jpg")
faces = app.get(img)
if faces:
    face = faces[0]
    print("Face attributes:", dir(face))
    print("Pose:", getattr(face, 'pose', 'Not found'))
