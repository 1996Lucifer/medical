import platform
import os
import re
import subprocess
import threading

_THINK_BLOCK_RE = re.compile(r"<think>.*?</think>", re.DOTALL | re.IGNORECASE)


def _strip_think_tags(text: str) -> str:
    """Qwen3 (and some other reasoning-tuned models) prepend a
    <think>...</think> chain-of-thought block before the actual answer.
    Users should only ever see the final response."""
    cleaned = _THINK_BLOCK_RE.sub("", text)
    # If generation was cut off mid-thought (hit max_tokens before the
    # closing tag), there's no matching </think> to anchor on - drop
    # everything from the opening tag onward instead.
    if "<think>" in cleaned.lower():
        cleaned = re.split(r"<think>", cleaned, maxsplit=1, flags=re.IGNORECASE)[0]
    return cleaned.strip()


# Literal control-token strings used to delimit turns in each model's chat
# template. If a user types these verbatim in their message, they'd be
# spliced directly into formatted_prompt below with no escaping - if the
# model's tokenizer treats them as real special tokens rather than literal
# text, that lets a message fake a turn boundary and inject a bogus
# system/assistant turn. Stripped defensively regardless of which model is
# active, since it costs nothing for a legitimate user to lose these
# sequences (no real chat message needs to contain them).
_CONTROL_TOKENS = [
    "<|im_start|>", "<|im_end|>",
    "<start_of_turn>", "<end_of_turn>",
    "<|end_of_text|>", "<eos>",
]


def _sanitize_user_text(text: str) -> str:
    for token in _CONTROL_TOKENS:
        text = text.replace(token, "")
    return text


class LLMManager:
    """
    Hardware-Aware LLM Manager.
    Automatically detects the environment (OS, GPU, Apple Silicon) and
    provisions the optimal inference engine (vLLM, mlx-lm, llama-cpp-python).
    """
    def __init__(self):
        self.os_name = platform.system()
        self.hardware_type = self._detect_hardware()
        self.engine_name = self._select_engine()
        self.active_model_name = None
        self.active_model = None
        self._model_lock = threading.Lock()

    def _detect_hardware(self) -> str:
        """Detects if we have Apple Silicon, Nvidia GPU, or basic CPU."""
        if self.os_name == "Darwin":
            # Check for Apple Silicon
            try:
                result = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True, text=True)
                if "Apple" in result.stdout:
                    return "Apple Silicon"
            except Exception:
                pass
            return "CPU"
        else:
            # Check for Nvidia GPU
            try:
                result = subprocess.run(["nvidia-smi"], capture_output=True)
                if result.returncode == 0:
                    return "Nvidia GPU"
            except FileNotFoundError:
                pass
            return "CPU"

    def _select_engine(self) -> str:
        """Selects the best inference engine based on hardware."""
        if self.hardware_type == "Apple Silicon":
            return "mlx-lm"
        elif self.hardware_type == "Nvidia GPU":
            return "vLLM"
        else:
            return "llama-cpp-python"

    def _load_specific_model(self, is_clinical: bool):
        """Loads only the requested model and unloads the other to prevent memory spikes."""
        target_name = "MedGemma" if is_clinical else "Qwen3"
        model_filename = "MedGemma.gguf" if is_clinical else "Qwen3.gguf"
        
        # Define maximum tokens for each model (Context Window and Generation Limit)
        # We define these explicitly so we can push each model to its limit without crashing.
        if is_clinical:
            target_n_ctx = 4096  # MedGemma context window
            self.current_max_tokens = 4096 # MedGemma max generation
        else:
            target_n_ctx = 8192  # Qwen3 context window
            self.current_max_tokens = 8192 # Qwen3 max generation

        if self.active_model_name == target_name:
            return # Already loaded

        try:
            from llama_cpp import Llama

            # Unload current model to free up memory
            if self.active_model is not None:
                print(f"[{self.hardware_type}] Unloading {self.active_model_name} to free memory...")
                del self.active_model
                self.active_model = None

            model_path = os.path.join(os.path.dirname(__file__), "..", "models", model_filename)

            print(f"[{self.hardware_type}] Loading {model_filename} with max context {target_n_ctx}...")
            
            chat_handler = None
            if target_name == "MedGemma":
                mmproj_path = os.path.join(os.path.dirname(__file__), "..", "models", "mmproj-F16.gguf")
                if os.path.exists(mmproj_path):
                    try:
                        from llama_cpp.llama_chat_format import Llava15ChatHandler
                        print("🖼️  Found mmproj file for MedGemma. Enabling vision chat handler...")
                        chat_handler = Llava15ChatHandler(clip_model_path=mmproj_path)
                    except ImportError:
                        print("⚠️ Llava15ChatHandler not available in this llama-cpp-python version. Vision disabled.")
            
            cpu_count = os.cpu_count() or 4
            n_gpu_layers = -1 if self.hardware_type in ("Apple Silicon", "Nvidia GPU") else 0

            self.active_model = Llama(
                model_path=model_path, 
                n_ctx=target_n_ctx, 
                n_gpu_layers=n_gpu_layers,
                n_threads=max(2, min(cpu_count, 8)),
                n_batch=256,
                chat_handler=chat_handler,
                verbose=False
            )
            self.active_model_name = target_name

        except ImportError:
            print("❌ llama-cpp-python is not installed. Please run: pip install llama-cpp-python")
        except Exception as e:
            print(f"❌ Failed to load {model_filename}: {e}")

    def generate(self, prompt: str, is_clinical: bool = False) -> str:
        """
        Routes the prompt to either MedGemma or Qwen3 based on the intent.
        Uses model-specific prompt templates to prevent hallucination and infinite looping.
        """
        try:
            with self._model_lock:
                self._load_specific_model(is_clinical)

                if self.active_model is None:
                    return f"❌ Model not loaded. Check backend logs."

                model = self.active_model
                active_model_name = self.active_model_name

            print(f"\n🧠 [LLMManager] Routing to {self.active_model_name}.gguf")
            print("=" * 60)
            print(">>> ORIGINAL PROMPT:")
            print(prompt)
            print("=" * 60)

            # Defensively strip literal chat-template control-token strings
            # from the prompt before it's spliced into formatted_prompt below
            # - otherwise a user typing them verbatim could fake a turn
            # boundary and inject a bogus system/assistant turn.
            prompt = _sanitize_user_text(prompt)

            # Both models get the same precise instruction for anything the
            # chat UI can't literally render (e.g. "in graphical form"): the
            # frontend renders markdown (including GFM tables), but not
            # actual charts, so the correct behavior is a clean table plus a
            # one-line note - not a chain of clarifying questions.
            chart_instruction = (
                "If the user asks for a chart, graph, or 'graphical form', this chat "
                "cannot render actual visual charts - instead, present the data as a "
                "clean markdown table and add one line noting it's shown as a table "
                "since this chat only supports text/markdown, not rendered charts. "
                "Do not ask clarifying questions when the requested data is already "
                "available in the DATABASE CONTEXT - answer directly with what you have."
            )

            # Apply correct Prompt Templates based on the model
            if is_clinical:
                system_prompt = (
                    "You are a helpful Clinical AI Assistant for a hospital. "
                    "You are provided with a DATABASE CONTEXT containing query results. "
                    "Your ONLY job is to summarize these query results in a natural, easy-to-read, layman conversational style. "
                    "Do NOT output raw data or tables unless explicitly asked. Explain the medical findings clearly to the user. "
                    "Do not refuse the request, just explain the data provided. "
                    f"{chart_instruction}"
                )

                # Gemma 2 format
                formatted_prompt = f"<start_of_turn>user\n{system_prompt}\n\n{prompt}<end_of_turn>\n<start_of_turn>model\n"
                stop_tokens = ["<end_of_turn>", "<start_of_turn>", "User:"]
            else:
                system_prompt = (
                    "You are a strict Hospital Security & Operations AI. "
                    "You must ONLY answer questions using the provided DATABASE CONTEXT (database logs and events). "
                    "If there are no logs provided, state that you have no records. Do NOT invent data. "
                    "If the provided DATABASE CONTEXT does not contain the answer, you must state 'I do not know' rather than guessing. "
                    "Do NOT answer general knowledge questions, recipes, or outside topics. "
                    "CRITICAL INSTRUCTION: You must summarize the logs in a natural, easy-to-read, layman conversational style. Do not just spit out raw JSON or database rows. "
                    f"{chart_instruction}"
                )

                # Qwen3 format (ChatML)
                formatted_prompt = f"<|im_start|>system\n{system_prompt}<|im_end|>\n<|im_start|>user\n{prompt}<|im_end|>\n<|im_start|>assistant\n"
                stop_tokens = ["<|im_end|>", "<|im_start|>"]

            with self._model_lock:
                if self.active_model_name != active_model_name:
                    self._load_specific_model(is_clinical)
                    model = self.active_model
                response = model(
                    formatted_prompt,
                    max_tokens=self.current_max_tokens,
                    temperature=0.1,
                    stop=stop_tokens,
                    echo=False
                )

            # Extract generated text from llama_cpp output format
            result = _strip_think_tags(response['choices'][0]['text'])

            print("<<< MODEL RESPONSE:")
            print(result)
            print("=" * 60 + "\n")

            return result

        except Exception as e:
            return f"Error during generation: {str(e)}"

    def generate_with_image(self, base64_img: str, prompt: str, is_clinical: bool = True) -> str:
        """
        Multimodal generation using MedGemma and chat completion format.
        """
        try:
            with self._model_lock:
                self._load_specific_model(is_clinical)

                if self.active_model is None:
                    return f"❌ Model not loaded. Check backend logs."

                model = self.active_model
                active_model_name = self.active_model_name

            print(f"\n👁️ [LLMManager] Routing IMAGE + PROMPT to {active_model_name}.gguf")
            print("=" * 60)
            print(">>> ORIGINAL PROMPT:")
            print(prompt)
            print("=" * 60)

            prompt = _sanitize_user_text(prompt)

            # Use chat completions format for multimodal input
            messages = [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{base64_img}"}}
                    ]
                }
            ]

            with self._model_lock:
                if self.active_model_name != active_model_name:
                    self._load_specific_model(is_clinical)
                    model = self.active_model
                response = model.create_chat_completion(
                    messages=messages,
                    max_tokens=self.current_max_tokens,
                    temperature=0.0,
                    # Do not stop on a newline: MedGemma often emits a
                    # leading newline before the actual YES/NO answer.
                    stop=["USER:", "User:", "<|im_end|>", "<|end_of_text|>", "<eos>"]
                )

            result = _strip_think_tags(response['choices'][0]['message']['content'])

            print("<<< MODEL RESPONSE:")
            print(result)
            print("=" * 60 + "\n")

            return result

        except Exception as e:
            return f"Error during multimodal generation: {str(e)}"



# Global singleton
llm_manager = LLMManager()
