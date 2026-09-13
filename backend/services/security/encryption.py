import os
from pathlib import Path

from cryptography.fernet import Fernet, InvalidToken

# Encrypts chat content (ConversationHistory.content, AgentMemory.fact) at
# rest, so a raw DB dump/backup doesn't expose plaintext PHI even though
# the real access-control gap is at the API layer (see routers/agent.py
# session ownership checks). Key comes from AGENT_CHAT_ENCRYPTION_KEY in
# production; falls back to a locally-persisted key file for dev/on-prem
# setups that haven't set it yet, so encrypted rows stay decryptable across
# restarts rather than silently generating a new (and thus useless) key
# every time the process starts.
_KEY_FILE = Path(__file__).parent.parent.parent / ".chat_encryption_key"


def _validate_key(key: bytes, source: str) -> bytes:
    try:
        Fernet(key)
    except (ValueError, TypeError) as e:
        raise RuntimeError(
            f"{source} does not contain a valid Fernet key ({e}). "
            f"A Fernet key must be exactly 32 url-safe base64-encoded bytes - "
            f"generate one with: python3 -c \"from cryptography.fernet import "
            f"Fernet; print(Fernet.generate_key().decode())\" and set it as "
            f"AGENT_CHAT_ENCRYPTION_KEY (or delete {_KEY_FILE} to have one "
            f"generated automatically)."
        ) from e
    return key


def _load_key() -> bytes:
    env_key = os.environ.get("AGENT_CHAT_ENCRYPTION_KEY")
    if env_key:
        return _validate_key(env_key.encode(), "AGENT_CHAT_ENCRYPTION_KEY")

    if _KEY_FILE.exists():
        return _validate_key(_KEY_FILE.read_bytes().strip(), str(_KEY_FILE))

    key = Fernet.generate_key()
    _KEY_FILE.write_bytes(key)
    try:
        os.chmod(_KEY_FILE, 0o600)
    except OSError:
        pass
    print(
        f"[Encryption] No AGENT_CHAT_ENCRYPTION_KEY set - generated a new key "
        f"at {_KEY_FILE}. For production, set AGENT_CHAT_ENCRYPTION_KEY to this "
        f"value in your environment/secrets manager instead of relying on this "
        f"file, and back it up: losing it makes existing encrypted chat "
        f"history permanently unreadable."
    )
    return key


_fernet = Fernet(_load_key())


def encrypt_text(plaintext: str) -> str:
    if plaintext is None:
        return plaintext
    return _fernet.encrypt(plaintext.encode()).decode()


def decrypt_text(ciphertext: str) -> str:
    if ciphertext is None:
        return ciphertext
    try:
        return _fernet.decrypt(ciphertext.encode()).decode()
    except (InvalidToken, ValueError):
        # Rows written before encryption was introduced are still plaintext -
        # return as-is rather than crashing the chat history view on them.
        return ciphertext
