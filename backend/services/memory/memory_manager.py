class MemoryManager:
    """
    Maintains short-term conversational memory.
    """
    def __init__(self):
        self.history = {}

    def add_message(self, session_id: str, role: str, content: str):
        if session_id not in self.history:
            self.history[session_id] = []
        
        self.history[session_id].append({"role": role, "content": content})
        
        # Trim context if too long
        if len(self.history[session_id]) > 10:
            self.history[session_id] = self.history[session_id][-10:]

    def get_history(self, session_id: str) -> list:
        return self.history.get(session_id, [])

memory_manager = MemoryManager()
