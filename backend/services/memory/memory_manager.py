from sqlalchemy.orm import Session
from models import ConversationHistory

class MemoryManager:
    """
    Maintains short-term conversational memory in the database.
    """
    def add_message(self, db: Session, session_id: str, role: str, content: str):
        history = ConversationHistory(
            session_id=session_id,
            role=role,
            content=content
        )
        db.add(history)
        db.commit()

    def get_history(self, db: Session, session_id: str, limit: int = 10) -> list:
        records = db.query(ConversationHistory).filter(
            ConversationHistory.session_id == session_id
        ).order_by(ConversationHistory.timestamp.desc()).limit(limit).all()
        
        # Reverse to get chronological order
        return [{"role": r.role, "content": r.content} for r in reversed(records)]

    def delete_session(self, db: Session, session_id: str):
        db.query(ConversationHistory).filter(
            ConversationHistory.session_id == session_id
        ).delete()
        db.commit()

memory_manager = MemoryManager()
