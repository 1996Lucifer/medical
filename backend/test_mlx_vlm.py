import os
import mlx.core as mx
from mlx_vlm import load, generate

model_path = os.path.join(os.path.dirname(__file__), "models", "MedGemma.gguf")
try:
    print("Loading MedGemma via mlx-vlm...")
    model, processor = load(model_path)
    print("Success!")
except Exception as e:
    print("Error:", e)
