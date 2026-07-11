import os
import cv2
import numpy as np
import base64
from llama_cpp import Llama
from llama_cpp.llama_chat_format import Gemma4ChatHandler

def test_medgemma():
    model_path = os.path.join(os.path.dirname(__file__), "models", "MedGemma.gguf")
    try:
        chat_handler = Gemma4ChatHandler(clip_model_path=model_path)
        llm = Llama(model_path=model_path, n_ctx=2048, verbose=False, chat_handler=chat_handler)
        
        dummy_img = np.zeros((224, 224, 3), dtype=np.uint8)
        _, buffer = cv2.imencode('.jpg', dummy_img)
        base64_img = base64.b64encode(buffer).decode('utf-8')
        
        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "Describe this image."},
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{base64_img}"}}
                ]
            }
        ]
        
        print("Sending chat completion request...")
        response = llm.create_chat_completion(messages=messages, max_tokens=100)
        print("Response:", response['choices'][0]['message']['content'])
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    test_medgemma()
