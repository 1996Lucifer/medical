from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session
from database import get_db
import models
import asyncio

router = APIRouter(prefix="/api/security", tags=["security"])

active_security_websockets = []

_security_loop = None

def broadcast_to_security_clients(message: str):
    if _security_loop and not _security_loop.is_closed():
        for ws in active_security_websockets:
            try:
                asyncio.run_coroutine_threadsafe(ws.send_text(message), _security_loop)
            except Exception as e:
                print(f"[Security WS] Broadcast error: {e}")

@router.websocket("/ws/alerts")
async def security_alerts_websocket(websocket: WebSocket):
    global _security_loop
    if _security_loop is None:
        _security_loop = asyncio.get_running_loop()
        
    await websocket.accept()
    active_security_websockets.append(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        active_security_websockets.remove(websocket)

from routers.auth import get_current_user

@router.get("/alerts")
def get_alerts(unresolved_only: bool = False, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    query = db.query(models.SecurityAlert)
    if unresolved_only:
        query = query.filter(models.SecurityAlert.resolved == False)
    
    alerts = query.order_by(models.SecurityAlert.timestamp.desc()).all()
    
    # Format with camera names
    result = []
    for alert in alerts:
        camera_name = alert.camera.name if alert.camera else "Unknown Camera"
        result.append({
            "id": alert.id,
            "rule_name": alert.rule_name,
            "severity": alert.severity,
            "camera_id": alert.camera_id,
            "camera_name": camera_name,
            "details": alert.details,
            "timestamp": alert.timestamp.isoformat() if alert.timestamp else None,
            "resolved": alert.resolved
        })
    return result

@router.post("/alerts/{alert_id}/resolve")
def resolve_alert(alert_id: int, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    alert = db.query(models.SecurityAlert).filter(models.SecurityAlert.id == alert_id).first()
    if not alert:
        raise HTTPException(status_code=404, detail="Alert not found")
        
    alert.resolved = True
    db.commit()
    return {"status": "success", "message": "Alert resolved"}
