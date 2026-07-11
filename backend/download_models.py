import os
import sys
from huggingface_hub import hf_hub_download

def install_and_download():
    print("Installing required libraries...")
    os.system(f"{sys.executable} -m pip install -q transformers torch huggingface_hub llama-cpp-python")

    print("\nDownloading the Tiny ML Router model...")
    try:
        from transformers import pipeline
        classifier = pipeline("zero-shot-classification", model="typeform/distilbert-base-uncased-mnli")
        print("✅ Tiny ML Router model downloaded and cached successfully!")
    except Exception as e:
        print(f"❌ Error downloading router model: {e}")

    print("\n" + "="*50)
    print("🏥 MAIN LLM MODELS (MedGemma / Qwen3)")
    print("="*50)
    models_dir = os.path.join(os.path.dirname(__file__), "models")
    os.makedirs(models_dir, exist_ok=True)
    
    # Download Unsloth MedGemma
    try:
        print("Downloading Unsloth MedGemma (Q4_K_M)...")
        hf_hub_download(
            repo_id="unsloth/medgemma-4b-it-GGUF",
            filename="medgemma-4b-it-Q4_K_M.gguf",
            local_dir=models_dir,
            local_dir_use_symlinks=False
        )
        # Rename to match our codebase expectation
        os.rename(os.path.join(models_dir, "medgemma-4b-it-Q4_K_M.gguf"), os.path.join(models_dir, "MedGemma.gguf"))
        
        print("Downloading mmproj projector...")
        hf_hub_download(
            repo_id="unsloth/medgemma-4b-it-GGUF",
            filename="mmproj-F16.gguf",
            local_dir=models_dir,
            local_dir_use_symlinks=False
        )
        print("✅ Unsloth MedGemma downloaded successfully!")
    except Exception as e:
        print(f"❌ Error downloading MedGemma: {e}")

if __name__ == "__main__":
    install_and_download()
