from typing import Optional

from sqlalchemy.orm import Session

import models
from routers.auth import has_permission


def effective_head(db: Session, staff: models.Staff) -> Optional[models.Staff]:
    """
    Who this staff member currently answers to, in priority order:

    1. An explicit `reports_to_id` (manually assigned - e.g. a nurse
       reporting directly to one specific doctor) always wins.
    2. Otherwise, whoever heads their `category` AND shares their
       `department` (a department-scoped head, e.g. "ICU" nurse head).
    3. Otherwise, whoever heads their `category` with no department set
       (that category's catch-all default head).
    4. Otherwise None - nobody has claimed this person yet. Admin/
       SuperAdmin already see and manage everyone regardless, so this
       isn't an error state, just "unassigned".

    A head's own row resolves through the same rules like anyone else's -
    a head is not automatically exempt, so a chain of heads (e.g. a
    department head reporting to a hospital-wide head) works without any
    special-casing here.
    """
    if staff.reports_to_id is not None:
        return staff.reports_to

    if staff.department:
        scoped = (
            db.query(models.Staff)
            .filter(
                models.Staff.category == staff.category,
                models.Staff.is_head.is_(True),
                models.Staff.department == staff.department,
                models.Staff.id != staff.id,
            )
            .first()
        )
        if scoped is not None:
            return scoped

    return (
        db.query(models.Staff)
        .filter(
            models.Staff.category == staff.category,
            models.Staff.is_head.is_(True),
            models.Staff.department.is_(None),
            models.Staff.id != staff.id,
        )
        .first()
    )


def would_create_cycle(db: Session, staff_id: int, new_reports_to_id: int) -> bool:
    """
    Walks the reports_to chain starting from `new_reports_to_id`. If it
    ever reaches `staff_id`, assigning that chain's head would make
    `staff_id` its own (indirect) senior - effective_head() would then
    loop forever trying to resolve anyone caught in the cycle.
    """
    current_id: Optional[int] = new_reports_to_id
    seen: set[int] = set()
    while current_id is not None:
        if current_id == staff_id:
            return True
        if current_id in seen:
            return False  # an existing, unrelated cycle - not this change's problem
        seen.add(current_id)
        row = db.query(models.Staff.reports_to_id).filter(models.Staff.id == current_id).first()
        current_id = row[0] if row else None
    return False


def can_assign(db: Session, actor_user: models.User, target: models.Staff) -> bool:
    """
    Who may change `target`'s department/reports_to_id - i.e. who counts
    as authorized to (re)assign this staff member, per the rule that
    reassignment is a head's call, not general manage_staff:

    - Anyone holding "manage_staff" (the existing staff-admin permission,
      which already short-circuits True for superadmin): always - matches
      their unconditional authority over everything else on a Staff row.
    - The staff member's CURRENT effective head: always - covers both
      "my report changes teams" and a head correcting their own team.
    - Any is_head in the target's OWN category, only when the target has
      no effective head yet: lets a head claim an unassigned staff member
      without a chicken-and-egg problem where nobody could ever make the
      first assignment.
    """
    if has_permission(actor_user, "manage_staff"):
        return True

    actor_staff = (
        db.query(models.Staff).filter(models.Staff.user_id == actor_user.id).first()
    )
    if actor_staff is None or not actor_staff.is_head:
        return False

    current_head = effective_head(db, target)
    if current_head is not None:
        return current_head.id == actor_staff.id

    return actor_staff.category == target.category
