import os
from transformers import pipeline
from PIL import Image
import numpy as np

def test_pipeline():
    model_path = os.path.join(os.path.dirname(__file__), "models", "MedGemma.gguf")
    try:
        print("Loading pipeline...")
        # try loading as image-text-to-text
        pipe = pipeline("image-text-to-text", model=model_path)
        
        dummy_img = Image.fromarray(np.zeros((224, 224, 3), dtype=np.uint8))
        print("Running pipeline...")
        result = pipe(dummy_img, prompt="What is this?")
        print("Result:", result)
    except Exception as e:
        print("Error:", e)

test_pipeline()
