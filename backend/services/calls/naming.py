from sqlalchemy.orm import Session

import models


def display_name(db: Session, user: models.User) -> str:
    """
    What to call this account in a conversation/call-log list: a staff
    record's name, else a patient's name, else the login username. Shared
    by routers/messages.py and routers/calls.py so a caller/callee who
    isn't in the People Directory at all (e.g. an admin/superadmin login
    with no Staff row) still resolves to something readable instead of a
    blank peer.
    """
    if user.role != "patient":
        staff = db.query(models.Staff).filter(models.Staff.user_id == user.id).first()
        if staff is not None:
            return staff.name
    if user.patient_profile is not None:
        return user.patient_profile.name
    return user.username
