from typing import Optional

from sqlalchemy.orm import Session

import models


def can_call(db: Session, caller: models.User, callee_user_id: int) -> bool:
    """
    Who's allowed to ring whom, over the call-signaling WebSocket:

    - A patient may only call a doctor they've actually been consulted by
      (Consultation.staff_id linking their Patient row to that Staff row) -
      never an arbitrary staff member or another patient.
    - A doctor (Staff.category == "Doctor") may call back any patient they
      have consulted, or any other staff/admin account freely.
    - Any other staff/admin account (nurse, security, admin, superadmin,
      ...) may call any other staff/admin account freely, but never a
      patient directly - only that patient's own doctor can call them.

    This is checked once, at call-invite time - the WebSocket relay itself
    is a dumb forwarder after that, same as kram's signaling design.
    """
    callee = db.query(models.User).filter(models.User.id == callee_user_id).first()
    if callee is None:
        return False

    if caller.role == "patient":
        patient = caller.patient_profile
        if patient is None:
            return False
        return (
            db.query(models.Consultation)
            .join(models.Staff, models.Staff.id == models.Consultation.staff_id)
            .filter(
                models.Consultation.patient_id == patient.id,
                models.Staff.user_id == callee_user_id,
            )
            .first()
            is not None
        )

    if callee.role == "patient":
        # Only that patient's own doctor may call them back.
        caller_staff = db.query(models.Staff).filter(models.Staff.user_id == caller.id).first()
        if caller_staff is None:
            return False
        callee_patient = callee.patient_profile
        if callee_patient is None:
            return False
        return (
            db.query(models.Consultation)
            .filter(
                models.Consultation.patient_id == callee_patient.id,
                models.Consultation.staff_id == caller_staff.id,
            )
            .first()
            is not None
        )

    # Staff/admin calling another staff/admin account: unrestricted.
    return True
