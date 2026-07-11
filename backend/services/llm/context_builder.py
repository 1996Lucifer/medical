from typing import List, Dict, Any

class ContextBuilder:
    """
    Formats retrieved SQL rows and vector chunks into structured prompts.
    """
    def build_context(self, rows: List[Dict[str, Any]], vector_chunks: List[str] = None, history: List[Dict[str, str]] = None, memory_facts: List[str] = None) -> str:
        context = "DATABASE CONTEXT:\n"
        
        if not rows and not vector_chunks:
            context += "No matching records found.\n"
        else:
            if rows:
                context += "--- Query Results ---\n"
                for i, row in enumerate(rows):
                    row_str = " | ".join([f"{k}: {v}" for k, v in row.items()])
                    context += f"- Row {i+1}: {row_str}\n"
                    
            if vector_chunks:
                context += "\n--- Knowledge Documents ---\n"
                for i, chunk in enumerate(vector_chunks):
                    context += f"- Chunk {i+1}: {chunk}\n"
                    
        if memory_facts:
            context += "\n--- LONG-TERM MEMORY FACTS ABOUT USER ---\n"
            for fact in memory_facts:
                context += f"- {fact}\n"

        context += "\nINSTRUCTIONS: You are a helpful, conversational AI Medical Assistant named Aura. Answer the user's question naturally and conversationally using the data provided in the context above. Format your answers nicely (e.g., use Markdown tables if the user asks for tabular data). If the context doesn't contain enough information, politely say so, but DO NOT invent data.\n"
        
        if history and len(history) > 0:
            context += "\n--- CHAT HISTORY ---\n"
            for msg in history:
                role = msg["role"].upper()
                context += f"{role}: {msg['content']}\n"
                
        return context

context_builder = ContextBuilder()
