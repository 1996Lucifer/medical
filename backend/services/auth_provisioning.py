import re
import secrets
import string

from sqlalchemy.orm import Session

import models
from routers.auth import get_password_hash

# Characters excluded from generated temp passwords: visually ambiguous
# (l/I/1/O/0) so an admin reading it aloud to a new hire/patient doesn't
# transcribe it wrong.
_TEMP_PASSWORD_ALPHABET = "".join(
    c for c in (string.ascii_letters + string.digits) if c not in "lIO01"
)


def generate_username(db: Session, name: str, fallback: str = "user") -> str:
    base = re.sub(r"[^a-z0-9]+", ".", name.strip().lower()).strip(".")
    if not base:
        base = fallback
    candidate = base
    suffix = 1
    while db.query(models.User).filter(models.User.username == candidate).first():
        suffix += 1
        candidate = f"{base}{suffix}"
    return candidate


def generate_temp_password(length: int = 10) -> str:
    return "".join(secrets.choice(_TEMP_PASSWORD_ALPHABET) for _ in range(length))


def create_login_account(
    db: Session, name: str, role: str, fallback_username: str = "user", commit: bool = True
):
    """
    Create a login account with a system-generated temporary password, in
    "change_password" status so the first login forces a change - the
    caller communicates this one-time password out of band, it is never
    stored or shown again. Returns (models.User, plaintext_temp_password),
    or (None, None) if account creation failed.

    commit=False lets a caller fold this creation into a larger
    transaction (e.g. alongside a Staff row) so the two share a single
    commit - the account is flushed (so new_user.id is available) but not
    committed, and it's the caller's responsibility to call db.commit().
    On failure this still rolls back the whole session, which is what
    makes commit=False safe to compose with other not-yet-committed
    objects: nothing partial is left behind.
    """
    try:
        username = generate_username(db, name, fallback=fallback_username)
        temp_password = generate_temp_password()
        new_user = models.User(
            username=username,
            hashed_password=get_password_hash(temp_password),
            role=role,
            status="change_password",
        )
        db.add(new_user)
        if commit:
            db.commit()
        else:
            db.flush()
        db.refresh(new_user)
        return new_user, temp_password
    except Exception as e:
        db.rollback()
        print(f"[AuthProvisioning] Failed to create login account for {name}: {e}")
        return None, None
