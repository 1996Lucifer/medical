import asyncio
from sqlalchemy.orm import Session
from models import AgentMemory
from services.llm_manager import llm_manager
from database import SessionLocal

class MemoryExtractor:
    """
    Background worker that analyzes conversations to extract and persist long-term memory facts.
    """
    def __init__(self):
        # We use a strict prompt to ensure we only extract valid facts.
        self.extraction_prompt = (
            "You are a strict Memory Extraction AI.\n"
            "Analyze the following conversation between a USER and an ASSISTANT.\n"
            "If the USER reveals a permanent fact about themselves, a personal preference, "
            "or a critical piece of operational context that should be remembered for future sessions, "
            "extract it as a concise, standalone sentence (e.g., 'The user is a radiologist.', 'The user prefers bullet points.').\n"
            "If there is NO new permanent fact, reply ONLY with 'NO_FACTS'.\n\n"
            "CONVERSATION:\n"
            "USER: {user_message}\n"
            "ASSISTANT: {assistant_message}\n\n"
            "Extract fact or NO_FACTS:"
        )

    def extract_and_save_background(self, session_id: str, user_message: str, assistant_message: str):
        """
        Runs the extraction in the background and saves to the database if a fact is found.
        """
        try:
            # 1. Ask LLM to extract facts
            prompt = self.extraction_prompt.format(
                user_message=user_message,
                assistant_message=assistant_message
            )
            
            # Use Qwen3 (default router model) for fast extraction
            result = llm_manager.generate(prompt, False)
            result = result.strip()
            
            # Remove <think> blocks from Qwen3
            import re
            result = re.sub(r'<think>.*?</think>', '', result, flags=re.DOTALL).strip()

            if result and "NO_FACTS" not in result.upper():
                print(f"[MemoryExtractor] Learned new fact for session {session_id}: {result}")
                
                # 2. Compute embedding (we can use the same embedding model as vector_retriever)
                from services.retrieval.vector_retriever import vector_retriever
                embedding = vector_retriever.embedding_model.encode(result).tolist()

                # 3. Save to database
                db = SessionLocal()
                try:
                    new_memory = AgentMemory(
                        session_id=session_id,
                        fact=result,
                        embedding=embedding
                    )
                    db.add(new_memory)
                    db.commit()
                finally:
                    db.close()
        except Exception as e:
            print(f"[MemoryExtractor] Error extracting memory: {e}")

memory_extractor = MemoryExtractor()
