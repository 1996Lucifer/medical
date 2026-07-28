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
                max_rows = 15
                for i, row in enumerate(rows[:max_rows]):
                    row_str = " | ".join([f"{k}: {v}" for k, v in row.items()])
                    if len(row_str) > 600:
                        row_str = row_str[:600] + "... [truncated]"
                    context += f"- Row {i+1}: {row_str}\n"
                if len(rows) > max_rows:
                    context += f"- ...and {len(rows) - max_rows} more rows not shown due to context limits.\n"
                    
            if vector_chunks:
                context += "\n--- Knowledge Documents ---\n"
                for i, chunk in enumerate(vector_chunks[:3]):
                    chunk_str = str(chunk)
                    if len(chunk_str) > 500:
                        chunk_str = chunk_str[:500] + "... [truncated]"
                    context += f"- Chunk {i+1}: {chunk_str}\n"
                    
        if memory_facts:
            context += "\n--- LONG-TERM MEMORY FACTS ABOUT USER ---\n"
            for fact in memory_facts:
                context += f"- {fact}\n"

        context += "\nINSTRUCTIONS: You are a helpful, conversational AI Medical Assistant named Aura. Answer the user's question naturally and conversationally using the data provided in the context above. Format your answers nicely (e.g., use Markdown tables if the user asks for tabular data). If the context doesn't contain enough information, politely say so, but DO NOT invent data.\n"
        
        if history and len(history) > 0:
            context += "\n--- CHAT HISTORY ---\n"
            for msg in history:
                role = msg["role"].upper()
                content = str(msg.get('content', ''))
                if len(content) > 1000:
                    content = content[:1000] + "... [truncated]"
                context += f"{role}: {content}\n"
                
        return context

context_builder = ContextBuilder()
