import time
import threading
from sqlalchemy.orm import Session
from models import AgentMemory
from services.routing.intent_router import intent_router
from services.routing.llm_router import llm_router
from services.entities.entity_extractor import entity_extractor
from services.gateway.query_planner import query_planner
from services.tools.tool_executor import tool_executor
from services.retrieval.vector_retriever import vector_retriever
from services.llm.context_builder import context_builder
from services.llm.response_formatter import response_formatter
from services.llm_manager import llm_manager
from services.metrics.metrics import metrics_tracker
from services.memory.memory_manager import memory_manager
from services.memory.memory_extractor import memory_extractor

class WorkflowEngine:
    """
    Controls the execution pipeline for AI requests.
    """
    def execute_workflow(self, message: str, db: Session, session_id: str = "default", base64_img: str = None) -> str:
        start_time = time.time()
        
        # 1. Intent Routing
        intent = intent_router.detect_intent(message)
        model_name = llm_router.route_to_model(intent) if not base64_img else "MedGemma (Vision)"
        is_clinical = (model_name == "MedGemma") or (base64_img is not None)

        # 2. Entity Extraction
        entities = entity_extractor.extract_entities(message)

        # 3. Query Planning
        strategy, tool_name = query_planner.plan_query(intent, entities, message)

        # 4. Retrieval (Tools / Vectors)
        rows = []
        vector_chunks = []
        
        if strategy == "SQL" and tool_name:
            rows = tool_executor.execute_tool(tool_name, entities, db)
        elif strategy == "VECTOR":
            vector_chunks = vector_retriever.search(message)

        # 5. Fetch Memory & History
        history = memory_manager.get_history(db, session_id, limit=5)
        
        memory_facts = []
        if not base64_img:
            # Retrieve relevant long-term memory facts via vector similarity
            try:
                query_embedding = vector_retriever.embedding_model.encode(message).tolist()
                memory_records = db.query(AgentMemory).filter(
                    AgentMemory.session_id == session_id
                ).order_by(AgentMemory.embedding.l2_distance(query_embedding)).limit(3).all()
                memory_facts = [m.fact for m in memory_records]
            except Exception as e:
                print(f"[WorkflowEngine] Failed to retrieve memory facts: {e}")

        # 6. LLM Formatting & Generation
        if strategy == "SQL" and not rows:
            response = "No matching records found."
        else:
            context = context_builder.build_context(rows, vector_chunks, history, memory_facts)
            final_prompt = f"{context}\nUSER QUESTION:\n{message}"
            
            # Pass to LLM
            if base64_img:
                response = llm_manager.generate_with_image(base64_img, final_prompt, is_clinical=True)
            else:
                response = llm_manager.generate(final_prompt, is_clinical=is_clinical)

        # Record metrics
        metrics_tracker.log_interaction({
            "intent": intent,
            "strategy": strategy,
            "tool_name": tool_name,
            "model": model_name,
            "latency": time.time() - start_time
        })
        
        # 7. Save to short-term memory
        memory_manager.add_message(db, session_id, "user", message)
        memory_manager.add_message(db, session_id, "assistant", response)
        
        # 8. Background Long-Term Memory Extraction
        threading.Thread(
            target=memory_extractor.extract_and_save_background,
            args=(session_id, message, response),
            daemon=True
        ).start()

        return response

workflow_engine = WorkflowEngine()
