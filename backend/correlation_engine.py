import datetime
from sqlalchemy.orm import Session
from sqlalchemy import asc
import models
import json

class CorrelationEngine:
    def get_timeline(self, db: Session, date: datetime.date, staff_name: str = None):
        """
        Builds a correlated timeline of events for a given day.
        Reconstructs the full path of staff across cameras using SystemEvents,
        resolving the 'AreaTransition' events into discrete location spans.
        """
        # Get start and end of day in UTC since DB stores in UTC
        start_dt = datetime.datetime.combine(date, datetime.time.min).replace(tzinfo=datetime.timezone.utc)
        end_dt = datetime.datetime.combine(date, datetime.time.max).replace(tzinfo=datetime.timezone.utc)

        # Query all events for the day
        query = db.query(models.SystemEvent).filter(
            models.SystemEvent.timestamp >= start_dt,
            models.SystemEvent.timestamp <= end_dt
        ).order_by(asc(models.SystemEvent.timestamp))

        events = query.all()

        timeline = []
        # State tracking for sessions
        # active_sessions = { "StaffName": {"start_time": t, "camera": "Cam1"} }
        active_sessions = {}

        for ev in events:
            details = {}
            if ev.details:
                try:
                    details = json.loads(ev.details)
                except:
                    pass

            # 1. Handle Attendance (Check-In)
            if ev.event_type == "Attendance":
                name = details.get("staff_name")
                if name:
                    if staff_name and name != staff_name:
                        continue
                        
                    # If already active, close it implicitly
                    if name in active_sessions:
                        prev = active_sessions[name]
                        timeline.append({
                            "type": "Session",
                            "staff_name": name,
                            "camera_name": prev["camera"],
                            "start_time": prev["start_time"],
                            "end_time": ev.timestamp,
                            "description": f"{name} left {prev['camera']}"
                        })
                        
                    active_sessions[name] = {
                        "start_time": ev.timestamp,
                        "camera": ev.camera_name or "Unknown"
                    }

            # 2. Handle Area Transitions
            elif ev.event_type == "AreaTransition":
                name = details.get("staff_name")
                if name:
                    if staff_name and name != staff_name:
                        continue
                        
                    if name in active_sessions:
                        prev = active_sessions[name]
                        # Finalize the span in the old camera
                        timeline.append({
                            "type": "SessionSpan",
                            "staff_name": name,
                            "camera_name": prev["camera"],
                            "start_time": prev["start_time"],
                            "end_time": ev.timestamp,
                            "description": f"Present at {prev['camera']}"
                        })
                    
                    active_sessions[name] = {
                        "start_time": ev.timestamp,
                        "camera": ev.camera_name or "Unknown"
                    }

            # 3. Handle standalone events (Unknown Faces, Security Alerts)
            elif ev.event_type in ["UnknownFaceDetected", "CameraOffline", "EquipmentDetection", "EquipmentMovement", "SecurityAlert"]:
                # If filtering by staff, only show staff-related events
                if staff_name and ev.event_type != "SecurityAlert":
                    continue
                    
                desc = f"Event: {ev.event_type}"
                if ev.event_type == "UnknownFaceDetected":
                    desc = "Unknown person detected"
                elif ev.event_type == "EquipmentMovement":
                    desc = f"Equipment moved: {details.get('equipment_id', 'Unknown')}"
                    
                timeline.append({
                    "type": "Standalone",
                    "staff_name": None,
                    "camera_name": ev.camera_name,
                    "start_time": ev.timestamp,
                    "end_time": ev.timestamp,
                    "description": desc,
                    "details": details
                })

        # Close out any still-active sessions for the day using the Attendance table's last_seen
        if active_sessions:
            today_attendance = db.query(models.Attendance).filter(
                models.Attendance.date == date
            ).all()
            
            last_seen_map = {a.staff_name: a.last_seen for a in today_attendance}
            
            for name, session in active_sessions.items():
                if staff_name and name != staff_name:
                    continue
                    
                end_time = last_seen_map.get(name, session["start_time"])
                timeline.append({
                    "type": "SessionSpan",
                    "staff_name": name,
                    "camera_name": session["camera"],
                    "start_time": session["start_time"],
                    "end_time": end_time,
                    "description": f"Present at {session['camera']}"
                })

        # Sort combined timeline descending
        timeline.sort(key=lambda x: x["start_time"], reverse=True)
        return timeline

correlation_engine = CorrelationEngine()
