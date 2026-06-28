import datetime
from sqlalchemy.orm import Session
from database import SessionLocal
import models

class SecurityRulesEngine:
    def __init__(self):
        pass

    def evaluate_event(self, event_type: str, camera_id: int, camera_name: str, confidence: float, details: dict):
        """
        Main entry point for evaluating events against security rules.
        Called asynchronously or directly after an event is published.
        """
        # Run specific rules
        self._check_theft_rule(event_type, camera_id, camera_name, confidence, details)
        self._check_restricted_access(event_type, camera_id, camera_name, confidence, details)
        self._check_unknown_face_offhours(event_type, camera_id, camera_name, confidence, details)
        self._check_ppe_compliance(event_type, camera_id, camera_name, confidence, details)

    def _check_theft_rule(self, event_type: str, camera_id: int, camera_name: str, confidence: float, details: dict):
        """
        Theft Detection:
        If Equipment Movement is detected, but no staff member has been detected
        at this camera in the last 60 seconds, flag as potential theft.
        """
        if event_type not in ["EquipmentMovement", "EquipmentDetection"]:
            return
            
        if not camera_id:
            return

        db: Session = SessionLocal()
        try:
            now = datetime.datetime.now(tz=datetime.timezone.utc)
            sixty_seconds_ago = now - datetime.timedelta(seconds=60)

            # Check if any staff was detected recently
            recent_staff = db.query(models.Attendance).filter(
                models.Attendance.camera_id == camera_id,
                models.Attendance.last_seen >= sixty_seconds_ago
            ).first()

            if not recent_staff:
                equip_id = details.get("equipment_id", "Unknown Equipment")
                import json
                
                alert_details = {
                    "reason": "Equipment moved without staff present",
                    "equipment_id": equip_id,
                    "confidence": confidence
                }
                
                alert = models.SecurityAlert(
                    rule_name="Theft Detection",
                    severity="high",
                    camera_id=camera_id,
                    details=json.dumps(alert_details),
                    timestamp=now
                )
                db.add(alert)
                db.commit()
                print(f"[Security] 🚨 THEFT ALERT: {equip_id} moved at {camera_name} without staff!")
                
                # Fetch camera to get RTSP URL for ONVIF trigger
                camera = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
                if camera:
                    from camera.onvif_service import trigger_camera_alarm_async
                    trigger_camera_alarm_async(camera.rtsp_url)
                    
                # Broadcast alert to WebSocket (Flutter frontend)
                self._broadcast_alert(alert, camera_name)
                
        except Exception as e:
            print(f"[RulesEngine] Error in theft rule: {e}")
        finally:
            db.close()


    def _check_restricted_access(self, event_type: str, camera_id: int, camera_name: str, confidence: float, details: dict):
        """
        Unauthorized Access:
        If an Attendance event (person detected) occurs on a camera marked as restricted.
        """
        if event_type != "Attendance":
            return
            
        if not camera_id:
            return

        db: Session = SessionLocal()
        try:
            camera = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
            if camera and camera.is_restricted:
                now = datetime.datetime.now(tz=datetime.timezone.utc)
                staff_name = details.get("staff_name", "Unknown Person")
                
                import json
                
                alert_details = {
                    "reason": "Person detected in restricted area",
                    "staff_name": staff_name,
                    "confidence": confidence
                }
                
                alert = models.SecurityAlert(
                    rule_name="Restricted Access",
                    severity="critical",
                    camera_id=camera_id,
                    details=json.dumps(alert_details),
                    timestamp=now
                )
                db.add(alert)
                db.commit()
                print(f"[Security] 🚨 RESTRICTED ACCESS ALERT: {staff_name} detected at {camera_name}!")
                
                from camera.onvif_service import trigger_camera_alarm_async
                trigger_camera_alarm_async(camera.rtsp_url)
                
                self._broadcast_alert(alert, camera_name)
                
        except Exception as e:
            print(f"[RulesEngine] Error in restricted access rule: {e}")
        finally:
            db.close()

    def _check_unknown_face_offhours(self, event_type: str, camera_id: int, camera_name: str, confidence: float, details: dict):
        if event_type != "UnknownFaceDetected":
            return
            
        now = datetime.datetime.now(tz=datetime.timezone.utc)
        hour = now.hour
        # Off-hours: 8 PM (20) to 6 AM (6) UTC
        if hour >= 20 or hour < 6:
            import json
            import urllib.request
            import os
            webhook_url = os.getenv("SECURITY_WEBHOOK_URL")
            
            payload = {
                "text": f"🚨 *Unknown Face Detected* during off-hours!\n*Camera*: {camera_name}\n*Time*: {now.strftime('%Y-%m-%d %H:%M:%S UTC')}"
            }
            
            print(f"[Security] Off-hours Unknown Face! Payload: {json.dumps(payload)}")
            
            if webhook_url:
                try:
                    req = urllib.request.Request(webhook_url, data=json.dumps(payload).encode('utf-8'), headers={'content-type': 'application/json'})
                    urllib.request.urlopen(req, timeout=5)
                except Exception as e:
                    print(f"[RulesEngine] Webhook failed: {e}")

    def _check_ppe_compliance(self, event_type: str, camera_id: int, camera_name: str, confidence: float, details: dict):
        if event_type != "Attendance":
            return
            
        if not camera_id:
            return

        has_mask = details.get("has_mask")
        # If mask check wasn't performed, ignore
        if has_mask is None or has_mask is True:
            return
            
        db: Session = SessionLocal()
        try:
            camera = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
            # If camera is restricted/critical, enforce PPE
            if camera and camera.is_restricted:
                now = datetime.datetime.now(tz=datetime.timezone.utc)
                staff_name = details.get("staff_name", "Unknown Person")
                
                import json
                
                alert_details = {
                    "reason": "Missing required PPE (Mask) in restricted zone",
                    "staff_name": staff_name,
                    "confidence": confidence
                }
                
                alert = models.SecurityAlert(
                    rule_name="PPE Violation",
                    severity="high",
                    camera_id=camera_id,
                    details=json.dumps(alert_details),
                    timestamp=now
                )
                db.add(alert)
                db.commit()
                print(f"[Security] 🚨 PPE ALERT: {staff_name} missing mask at {camera_name}!")
                
                self._broadcast_alert(alert, camera_name)
                
        except Exception as e:
            print(f"[RulesEngine] Error in PPE compliance rule: {e}")
        finally:
            db.close()

    def _broadcast_alert(self, alert: models.SecurityAlert, camera_name: str):
        """
        Pushes the alert to the security websocket so Flutter can play an alarm.
        """
        import json
        from routers.security import broadcast_to_security_clients
        
        alert_data = {
            "id": alert.id,
            "rule_name": alert.rule_name,
            "severity": alert.severity,
            "camera_id": alert.camera_id,
            "camera_name": camera_name,
            "details": alert.details,
            "timestamp": alert.timestamp.isoformat() if alert.timestamp else None,
            "resolved": alert.resolved
        }
        
        broadcast_to_security_clients(json.dumps(alert_data))

security_rules_engine = SecurityRulesEngine()
