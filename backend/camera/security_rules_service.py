"""
Resolves which PPE items actually apply to a given staff member in a given
zone — mask included. Every item, mask or glove, comes exclusively from a
"Security Rule" the admin actually configures in the Rules-mode graph
editor (Entities -> Conditions -> Target Zones). Nothing is required by
default. Previously the vision pipeline hardcoded "mask + left glove +
right glove" for every zone tagged Verification/Restricted regardless of
what was ever configured, so unmapped roles/zones got false violations.

Rules are stored as `models.SecurityRule` rows with a free-text `rule_text`
(e.g. "doctors must wear gloves") and an optional `target_area` (e.g. "ICU",
or None/"global" to apply everywhere). Cached in memory and refreshed
periodically so the hot per-frame compliance check never hits the DB.
"""
import threading
import time
from typing import List, Optional, Set

_CACHE_TTL_SEC = 15.0

_lock = threading.Lock()
_cached_rules: List["_Rule"] = []
_cache_loaded_at: float = 0.0


class _Rule:
    __slots__ = ("rule_text", "target_area")

    def __init__(self, rule_text: str, target_area: Optional[str]):
        self.rule_text = rule_text.lower()
        self.target_area = (target_area or "").strip().lower()


# Role prefixes recognized in rule_text, matching how rules are phrased by
# the graph editor ("Doctors must wear face mask", "All Staff must ...").
_ROLE_PREFIXES = {
    "dr": "doctors",
    "doc": "doctors",
    "nurse": "nurses",
    "compounder": "compounders",
}


def _staff_roles(staff_name: str) -> List[str]:
    """Map a recognized staff name to the role labels rules are written against."""
    roles = ["all staff"]
    name_lower = staff_name.strip().lower()
    for prefix, role in _ROLE_PREFIXES.items():
        if name_lower.startswith(prefix):
            roles.append(role)
            break
    return roles


def _refresh_cache_if_stale() -> None:
    global _cached_rules, _cache_loaded_at
    now = time.monotonic()
    if _cached_rules and (now - _cache_loaded_at) < _CACHE_TTL_SEC:
        return

    with _lock:
        # Re-check inside the lock in case another thread just refreshed it.
        if _cached_rules and (time.monotonic() - _cache_loaded_at) < _CACHE_TTL_SEC:
            return
        try:
            from database import SessionLocal
            import models

            db = SessionLocal()
            try:
                rows = (
                    db.query(models.SecurityRule)
                    .filter(models.SecurityRule.is_active == True)  # noqa: E712
                    .all()
                )
                _cached_rules = [_Rule(r.rule_text, r.target_area) for r in rows]
            finally:
                db.close()
        except Exception as e:
            print(f"[SecurityRulesService] Failed to load security rules: {e}")
            _cached_rules = _cached_rules or []
        _cache_loaded_at = time.monotonic()


def _zone_matches(rule_target_area: str, zone_name: Optional[str]) -> bool:
    if not rule_target_area or rule_target_area == "global":
        return True
    if not zone_name:
        return False
    zone_lower = zone_name.lower()
    # Zones are drawn as free-text names like "Testing Table - ICU" while a
    # rule's target_area is a short label like "ICU" — match either way as a
    # substring so a rule doesn't need to spell the zone name exactly.
    return rule_target_area in zone_lower or zone_lower in rule_target_area


def get_required_ppe_items(staff_name: str, zone_name: Optional[str]) -> Set[str]:
    """
    Return the set of PPE items ({"mask", "left glove", "right glove"}) that
    the configured Security/AI Rules actually require for this staff member
    in this zone — mask included. Nothing is required by default: every
    item comes exclusively from a rule actually mapped in the graph editor
    for this person's role and this zone. An empty set means no rule was
    mapped here at all, so nothing should be verified or alerted on.
    """
    if staff_name == "Unknown":
        return set()

    _refresh_cache_if_stale()
    roles = _staff_roles(staff_name)

    required: Set[str] = set()
    for rule in _cached_rules:
        if not any(rule.rule_text.startswith(role) for role in roles):
            continue
        if not _zone_matches(rule.target_area, zone_name):
            continue
        if "glove" in rule.rule_text:
            required.add("left glove")
            required.add("right glove")
        if "mask" in rule.rule_text:
            required.add("mask")
    return required
