import cv2
from camera.model_manager import ModelManager
import numpy as np
import urllib.request

urllib.request.urlretrieve("https://raw.githubusercontent.com/deepinsight/insightface/master/sample-images/t1.jpg", "t1.jpg")
img = cv2.imread("t1.jpg")

app = ModelManager().get_face_analysis()
app.prepare(ctx_id=0, det_size=(640, 640))
try:
    faces = app.get(img)
    print("Faces found (with prepare):", len(faces))
except Exception as e:
    print("Error (with prepare):", e)

app2 = ModelManager().get_face_analysis() # singleton
try:
    faces2 = app2.get(img)
    print("Faces found (second time):", len(faces2))
except Exception as e:
    print("Error (second time):", e)
