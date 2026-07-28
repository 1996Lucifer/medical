"""
Compliance Engine — Zone-Based PPE Verification Token Manager.

Instead of checking PPE every frame, this engine stores verification tokens
that are valid for a configurable duration. Any camera can check if a person
is already verified via O(1) in-memory lookup.

Workflow:
    1. Person enters Verification Zone → start_verification()
    2. VLM confirms mask + gloves → record_verification()
    3. Person enters Restricted Zone → is_verified() returns True
    4. Token expires after VERIFICATION_EXPIRY_SEC → auto-cleanup
"""
import datetime
import threading
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional

from camera.constants.vision_constants import VERIFICATION_EXPIRY_SEC


@dataclass
class VerificationToken:
    """In-memory PPE compliance token for a single person."""

    staff_name: str
    camera_id: Optional[int] = None
    has_mask: bool = False
    has_left_glove: bool = False
    has_right_glove: bool = False
    confidence: float = 0.0
    verified_at: Optional[datetime.datetime] = None
    expires_at: Optional[datetime.datetime] = None
    # Track the verification workflow state
    state: str = "pending"  # pending | verifying | verified | expired | failed

    @property
    def is_verified(self) -> bool:
        """Check if all PPE items are confirmed and token hasn't expired."""
        if self.state != "verified":
            return False
        if self.expires_at is None:
            return False
        now = datetime.datetime.now(tz=datetime.timezone.utc)
        return now < self.expires_at

    @property
    def is_expired(self) -> bool:
        if self.expires_at is None:
            return self.state != "pending" and self.state != "verifying"
        now = datetime.datetime.now(tz=datetime.timezone.utc)
        return now >= self.expires_at

    @property
    def missing_items(self) -> List[str]:
        """Return list of PPE items that haven't been verified yet."""
        missing = []
        if not self.has_mask:
            missing.append("mask")
        if not self.has_left_glove:
            missing.append("left glove")
        if not self.has_right_glove:
            missing.append("right glove")
        return missing

    @property
    def all_ppe_confirmed(self) -> bool:
        return self.has_mask and self.has_left_glove and self.has_right_glove


class ComplianceEngine:
    """
    Stateful compliance engine managing verification tokens.

    Thread-safe. Used by the camera worker from a background thread
    and by compliance service from the async event loop.
    """

    def __init__(self, expiry_sec: int = VERIFICATION_EXPIRY_SEC):
        self._tokens: Dict[str, VerificationToken] = {}
        self._lock = threading.Lock()
        self._expiry_sec = expiry_sec

        # Start background cleanup thread
        self._cleanup_thread = threading.Thread(
            target=self._cleanup_loop, daemon=True
        )
        self._cleanup_thread.start()

    # ── Fast-Path Lookups ─────────────────────────────────────────────────────

    def is_verified(self, staff_name: str) -> bool:
        """O(1) check if a person has a valid, non-expired compliance token."""
        with self._lock:
            token = self._tokens.get(staff_name)
            if token is None:
                return False
            return token.is_verified

    def get_token(self, staff_name: str) -> Optional[VerificationToken]:
        """Get the current verification token for a person (if any)."""
        with self._lock:
            return self._tokens.get(staff_name)

    def get_missing_items(self, staff_name: str) -> List[str]:
        """Get list of PPE items still missing for an active verification."""
        with self._lock:
            token = self._tokens.get(staff_name)
            if token is None:
                return ["mask", "left glove", "right glove"]
            return token.missing_items

    # ── Verification Lifecycle ────────────────────────────────────────────────

    def start_verification(
        self, staff_name: str, camera_id: Optional[int] = None
    ) -> VerificationToken:
        """
        Start a new verification workflow for a person.
        Called when a person enters a Verification Zone and is not yet verified.
        """
        with self._lock:
            existing = self._tokens.get(staff_name)
            # Don't restart if already verifying or verified and not expired, or failed and in cooldown
            if existing and (
                existing.state == "verifying"
                or (existing.state == "verified" and not existing.is_expired)
                or (existing.state == "failed" and not existing.is_expired)
            ):
                return existing

            token = VerificationToken(
                staff_name=staff_name,
                camera_id=camera_id,
                state="verifying",
            )
            self._tokens[staff_name] = token
            print(
                f"[ComplianceEngine] 🔄 Verification started for {staff_name}"
            )
            return token

    def update_mask(
        self, staff_name: str, has_mask: bool, confidence: float = 0.0
    ) -> None:
        """Update mask verification result for a person."""
        with self._lock:
            token = self._tokens.get(staff_name)
            if token and token.state == "verifying":
                token.has_mask = has_mask
                token.confidence = max(token.confidence, confidence)
                self._maybe_complete(token)

    def update_left_glove(
        self, staff_name: str, has_glove: bool, confidence: float = 0.0
    ) -> None:
        """Update left glove verification result for a person."""
        with self._lock:
            token = self._tokens.get(staff_name)
            if token and token.state == "verifying":
                token.has_left_glove = has_glove
                token.confidence = max(token.confidence, confidence)
                self._maybe_complete(token)

    def update_right_glove(
        self, staff_name: str, has_glove: bool, confidence: float = 0.0
    ) -> None:
        """Update right glove verification result for a person."""
        with self._lock:
            token = self._tokens.get(staff_name)
            if token and token.state == "verifying":
                token.has_right_glove = has_glove
                token.confidence = max(token.confidence, confidence)
                self._maybe_complete(token)

    def record_verification(
        self,
        staff_name: str,
        has_mask: bool,
        has_left_glove: bool,
        has_right_glove: bool,
        confidence: float = 0.0,
        camera_id: Optional[int] = None,
    ) -> VerificationToken:
        """
        Record a complete verification result at once.
        Used when VLM returns all results simultaneously.
        """
        now = datetime.datetime.now(tz=datetime.timezone.utc)
        with self._lock:
            token = self._tokens.get(staff_name)
            if token is None:
                token = VerificationToken(staff_name=staff_name)
                self._tokens[staff_name] = token

            token.has_mask = has_mask
            token.has_left_glove = has_left_glove
            token.has_right_glove = has_right_glove
            token.confidence = confidence
            token.camera_id = camera_id

            if token.all_ppe_confirmed:
                token.state = "verified"
                token.verified_at = now
                token.expires_at = now + datetime.timedelta(
                    seconds=self._expiry_sec
                )
                print(
                    f"[ComplianceEngine] ✅ {staff_name} VERIFIED "
                    f"(expires in {self._expiry_sec}s, confidence={confidence:.2f})"
                )
            else:
                token.state = "failed"
                token.expires_at = now + datetime.timedelta(seconds=15)
                print(
                    f"[ComplianceEngine] ❌ {staff_name} FAILED verification. "
                    f"Missing: {token.missing_items}"
                )
            return token

    def revoke(
        self,
        staff_name: str,
        reason: str = "manual",
        missing_items: Optional[List[str]] = None,
    ) -> None:
        """Revoke a verification token (e.g., mask removed in restricted zone)."""
        with self._lock:
            token = self._tokens.get(staff_name)
            if token:
                for item in missing_items or []:
                    if item == "mask":
                        token.has_mask = False
                    elif item == "left glove":
                        token.has_left_glove = False
                    elif item == "right glove":
                        token.has_right_glove = False
                token.state = "expired"
                token.expires_at = datetime.datetime.now(
                    tz=datetime.timezone.utc
                )
                print(
                    f"[ComplianceEngine] ⚠️ {staff_name} verification REVOKED: {reason}"
                )

    def clear(self, staff_name: str) -> None:
        """Remove a verification token entirely."""
        with self._lock:
            self._tokens.pop(staff_name, None)

    # ── Bulk Queries ──────────────────────────────────────────────────────────

    def get_all_active(self) -> List[VerificationToken]:
        """Return all currently verified (non-expired) tokens."""
        with self._lock:
            return [t for t in self._tokens.values() if t.is_verified]

    def get_all_tokens(self) -> Dict[str, VerificationToken]:
        """Return a snapshot of all tokens for debugging/UI."""
        with self._lock:
            return dict(self._tokens)

    def to_dict(self, staff_name: str) -> Optional[dict]:
        """Serialize a token to a JSON-safe dict."""
        with self._lock:
            token = self._tokens.get(staff_name)
            if token is None:
                return None
            return {
                "person": token.staff_name,
                "mask": token.has_mask,
                "left_glove": token.has_left_glove,
                "right_glove": token.has_right_glove,
                "verified": token.is_verified,
                "state": token.state,
                "confidence": token.confidence,
                "verified_at": (
                    token.verified_at.isoformat() if token.verified_at else None
                ),
                "expires_at": (
                    token.expires_at.isoformat() if token.expires_at else None
                ),
            }

    # ── Internal ──────────────────────────────────────────────────────────────

    def _maybe_complete(self, token: VerificationToken) -> None:
        """Check if all PPE items are confirmed and auto-complete verification."""
        if token.all_ppe_confirmed:
            now = datetime.datetime.now(tz=datetime.timezone.utc)
            token.state = "verified"
            token.verified_at = now
            token.expires_at = now + datetime.timedelta(
                seconds=self._expiry_sec
            )
            print(
                f"[ComplianceEngine] ✅ {token.staff_name} VERIFIED "
                f"(all PPE confirmed, expires in {self._expiry_sec}s)"
            )

    def _cleanup_loop(self) -> None:
        """Background thread that expires stale tokens every 30 seconds."""
        while True:
            time.sleep(30)
            expired_names = []
            with self._lock:
                for name, token in self._tokens.items():
                    if token.is_expired and token.state not in (
                        "expired",
                        "pending",
                    ):
                        token.state = "expired"
                        expired_names.append(name)
            for name in expired_names:
                print(
                    f"[ComplianceEngine] ⏰ {name} verification EXPIRED."
                )

    def persist_to_db(self, staff_name: str) -> None:
        """Persist a verification token to the database for audit trail."""
        token = self.get_token(staff_name)
        if token is None:
            return

        try:
            from database import SessionLocal
            import models

            db = SessionLocal()
            record = models.PersonVerification(
                staff_name=token.staff_name,
                camera_id=token.camera_id,
                has_mask=token.has_mask,
                has_left_glove=token.has_left_glove,
                has_right_glove=token.has_right_glove,
                is_verified=token.is_verified,
                confidence=token.confidence,
                verified_at=token.verified_at,
                expires_at=token.expires_at,
            )
            db.add(record)
            db.commit()
            db.close()
        except Exception as e:
            print(f"[ComplianceEngine] DB persist error: {e}")


# Global singleton
compliance_engine = ComplianceEngine()
