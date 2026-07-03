import cv2
import numpy as np
import sys

def variance_of_laplacian(image):
    return cv2.Laplacian(image, cv2.CV_64F).var()

if __name__ == "__main__":
    # Can't test on the exact image easily without the image file, but I will write the script 
    # to demonstrate what I will do.
    pass
