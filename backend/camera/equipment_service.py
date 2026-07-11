import datetime
from typing import Optional

from database import SessionLocal
import models
from events import event_engine

def _maybe_track_equipment(
    equip_class: str, track_id: int, score: float,
    camera_id: Optional[int] = None,
    camera_name: Optional[str] = None,
):
    """
    Log equipment detection.
    Update its location if it moved.
    """
    db = SessionLocal()
    try:
        now = datetime.datetime.now(tz=datetime.timezone.utc)
        equip_id_str = f"{equip_class} #{track_id}"

        # Ensure type exists
        eq_type = db.query(models.EquipmentType).filter(models.EquipmentType.name == equip_class).first()
        if not eq_type:
            eq_type = models.EquipmentType(name=equip_class)
            db.add(eq_type)
            db.commit()
            db.refresh(eq_type)

        # Ensure item exists
        item = db.query(models.EquipmentItem).filter(models.EquipmentItem.equipment_id == equip_id_str).first()
        if not item:
            item = models.EquipmentItem(
                equipment_id=equip_id_str,
                type_id=eq_type.id,
                current_location=camera_name,
                last_seen=now
            )
            db.add(item)
            db.commit()
            db.refresh(item)

            # Log new detection
            event_engine.publish_event(
                event_type="EquipmentDetection",
                camera_id=camera_id,
                camera_name=camera_name,
                confidence=score,
                details={"equipment_id": equip_id_str, "status": "newly_detected"}
            )
        else:
            # Update location if changed
            if item.current_location != camera_name or (now - item.last_seen.replace(tzinfo=datetime.timezone.utc)).total_seconds() > 60:
                item.current_location = camera_name
                item.last_seen = now

                track_log = models.EquipmentTracking(
                    equipment_item_id=item.id,
                    camera_id=camera_id,
                    camera_name=camera_name,
                    timestamp=now
                )
                db.add(track_log)
                db.commit()

                # Emit event on location change
                event_engine.publish_event(
                    event_type="EquipmentMovement",
                    camera_id=camera_id,
                    camera_name=camera_name,
                    confidence=score,
                    details={"equipment_id": equip_id_str, "status": "moved"}
                )

    except Exception as e:
        print(f"[EquipmentTracking] Error for {equip_class}: {e}")
        db.rollback()
    finally:
        db.close()
