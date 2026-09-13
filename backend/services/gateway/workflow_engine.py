import time
import threading
from typing import Any, Dict, Optional
from sqlalchemy.orm import Session
from models import AgentMemory
from services.routing.intent_router import intent_router
from services.routing.llm_router import llm_router
from services.entities.entity_extractor import entity_extractor
from services.gateway.query_planner import query_planner
from services.tools.tool_executor import tool_executor, ToolAccessDenied
from services.retrieval.vector_retriever import vector_retriever
from services.llm.context_builder import context_builder
from services.llm.response_formatter import response_formatter
from services.llm.chart_builder import build_chart_spec
from services.llm_manager import llm_manager
from services.metrics.metrics import metrics_tracker
from services.memory.memory_manager import memory_manager
from services.memory.memory_extractor import memory_extractor
from services.security.encryption import decrypt_text

class WorkflowEngine:
    """
    Controls the execution pipeline for AI requests.
    """

    # Max L2 distance (all-MiniLM-L6-v2 embeddings) for a stored memory fact
    # to be considered relevant enough to inject into the prompt. Without
    # this, the nearest-3 lookup below always returns *something* even when
    # nothing stored is actually related to the current message, and the
    # LLM ends up mixing unrelated facts (e.g. camera logs from an earlier
    # turn) into an answer about a completely different topic.
    MEMORY_RELEVANCE_THRESHOLD = 0.8
    def execute_workflow(
        self,
        message: str,
        db: Session,
        session_id: str = "default",
        base64_img: str = None,
        user_id: Optional[int] = None,
        role: Optional[str] = None,
    ) -> Dict[str, Any]:
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
            try:
                rows = tool_executor.execute_tool(tool_name, entities, db, role=role)
            except ToolAccessDenied:
                # Don't silently fall through to the LLM with no data (it
                # might hallucinate an answer) or leak which tool exists -
                # just tell the user plainly that this needs a different role.
                return {
                    "text": (
                        "I can't share that - your account role doesn't have "
                        "permission to access this information. Please contact "
                        "an administrator if you believe this is incorrect."
                    ),
                    "chart": None,
                }
        elif strategy == "VECTOR":
            vector_chunks = vector_retriever.search(message)

        # 5. Fetch Memory & History
        history = memory_manager.get_history(db, session_id, limit=5)
        
        memory_facts = []
        if not base64_img:
            # Retrieve relevant long-term memory facts via vector similarity
            try:
                query_embedding = vector_retriever.embedding_model.encode(message).tolist()
                distance = AgentMemory.embedding.l2_distance(query_embedding)
                memory_records = db.query(AgentMemory, distance.label("distance")).filter(
                    AgentMemory.session_id == session_id
                ).order_by(distance).limit(3).all()
                memory_facts = [
                    decrypt_text(m.fact) for m, dist in memory_records
                    if dist is not None and dist <= self.MEMORY_RELEVANCE_THRESHOLD
                ]
            except Exception as e:
                print(f"[WorkflowEngine] Failed to retrieve memory facts: {e}")

        # 6. LLM Formatting & Generation
        context = context_builder.build_context(rows, vector_chunks, history, memory_facts)
        final_prompt = f"{context}\nUSER QUESTION:\n{message}"
        
        # Pass to LLM
        if base64_img:
            response = llm_manager.generate_with_image(base64_img, final_prompt, is_clinical=True)
        else:
            response = llm_manager.generate(final_prompt, is_clinical=is_clinical)

        # Built directly from the real SQL rows (never from anything the LLM
        # said), so the chart can't show hallucinated numbers. Only produced
        # when the user actually asked for a chart/graph/plot - a request
        # for "tabular"/table data is unaffected and keeps the normal
        # markdown-table response the system prompt already produces.
        chart = build_chart_spec(rows, message) if not base64_img else None

        # Record metrics
        metrics_tracker.log_interaction({
            "intent": intent,
            "strategy": strategy,
            "tool_name": tool_name,
            "model": model_name,
            "latency": time.time() - start_time
        })

        # 7. Save to short-term memory
        memory_manager.add_message(db, session_id, "user", message, user_id=user_id)
        memory_manager.add_message(db, session_id, "assistant", response, user_id=user_id)

        # 8. Background Long-Term Memory Extraction
        threading.Thread(
            target=memory_extractor.extract_and_save_background,
            args=(session_id, message, response),
            daemon=True
        ).start()

        return {"text": response, "chart": chart}

workflow_engine = WorkflowEngine()
