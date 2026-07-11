from transformers import AutoModelForVision2Seq, AutoProcessor
try:
    print("Loading MedGemma via Transformers...")
    model = AutoModelForVision2Seq.from_pretrained("./models/MedGemma.gguf")
    print("Success!")
except Exception as e:
    print("Error:", e)
