import datetime
from typing import Optional

from sqlalchemy.orm import Session
from models import ConversationHistory, AgentMemory
from services.security.encryption import encrypt_text, decrypt_text


class MemoryManager:
    """
    Maintains short-term conversational memory in the database.
    """
    def add_message(self, db: Session, session_id: str, role: str, content: str, user_id: Optional[int] = None):
        history = ConversationHistory(
            session_id=session_id,
            user_id=user_id,
            role=role,
            content=encrypt_text(content),
        )
        db.add(history)
        db.commit()

    def get_history(self, db: Session, session_id: str, limit: int = 10) -> list:
        records = db.query(ConversationHistory).filter(
            ConversationHistory.session_id == session_id
        ).order_by(ConversationHistory.timestamp.desc()).limit(limit).all()

        # Reverse to get chronological order
        return [{"role": r.role, "content": decrypt_text(r.content)} for r in reversed(records)]

    def get_session_owner(self, db: Session, session_id: str) -> Optional[int]:
        """
        Returns the user_id that first wrote to this session, or None if the
        session doesn't exist yet (a brand-new session_id, not yet owned by
        anyone) or if its rows predate user_id tracking. Used to enforce
        that a session can only be read/deleted/appended to by the user who
        started it (see routers/agent.py).
        """
        record = db.query(ConversationHistory).filter(
            ConversationHistory.session_id == session_id,
            ConversationHistory.user_id.isnot(None),
        ).order_by(ConversationHistory.timestamp.asc()).first()
        return record.user_id if record else None

    def delete_session(self, db: Session, session_id: str):
        db.query(ConversationHistory).filter(
            ConversationHistory.session_id == session_id
        ).delete()
        # AgentMemory rows (services/memory/memory_extractor.py) are keyed
        # by session_id but have no FK/cascade back to ConversationHistory -
        # without this they'd be orphaned forever once the owning session
        # is deleted.
        db.query(AgentMemory).filter(
            AgentMemory.session_id == session_id
        ).delete()
        db.commit()

    def purge_expired_memories(self, db: Session, ttl_days: int = 90) -> int:
        """
        Deletes AgentMemory rows older than `ttl_days`. Not currently wired
        into a scheduler - this is a callable a future periodic job (e.g. a
        cron task or APScheduler job started alongside the FastAPI app)
        can invoke to enforce a retention policy on long-term memory facts.
        Returns the number of rows deleted.
        """
        cutoff = datetime.datetime.now(tz=datetime.timezone.utc) - datetime.timedelta(days=ttl_days)
        deleted = db.query(AgentMemory).filter(
            AgentMemory.created_at < cutoff
        ).delete()
        db.commit()
        return deleted

memory_manager = MemoryManager()
