from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
import datetime

from database import get_db
import models

router = APIRouter(prefix="/api/analytics", tags=["analytics"])

# A staff member's total worked hours for the day within +/- this many hours
# of their expected shift length counts as "on_time" rather than under/over
# - avoids flagging someone as "shortfall" for clocking out 3 minutes early.
SHIFT_COMPLIANCE_TOLERANCE_HOURS = 0.25


@router.get("/attendance-summary")
def get_attendance_summary(days: int = 7, db: Session = Depends(get_db)):
    """
    Returns a daily summary of attendance for the last `days` days.
    """
    start_date = datetime.date.today() - datetime.timedelta(days=days)

    records = db.query(models.Attendance).filter(
        models.Attendance.date >= start_date
    ).all()

    summary = {}
    total_hours = 0.0
    active_staff = set()
    # (date, staff_id or staff_name) -> accumulated actual hours. A staff
    # member can have multiple Attendance *sessions* in one day (the 5-hour
    # gap rule in camera/attendance_service.py splits them), so shift
    # shortfall/overtime has to be computed on the day's total, not any one
    # session's duration_hours.
    daily_totals: dict = {}

    for record in records:
        date_str = record.date.isoformat()
        if date_str not in summary:
            summary[date_str] = []

        exit_time = record.exit_time or record.last_seen
        if exit_time and record.entry_time:
            duration = (exit_time - record.entry_time).total_seconds() / 3600.0
        else:
            duration = 0.0

        summary[date_str].append({
            "staff_name": record.staff_name,
            "entry_time": record.entry_time.isoformat() if record.entry_time else None,
            "exit_time": exit_time.isoformat() if exit_time else None,
            "duration_hours": round(duration, 2),
            "camera_name": record.camera_name,
        })

        total_hours += duration
        active_staff.add(record.staff_name)

        key = (date_str, record.staff_id if record.staff_id is not None else record.staff_name)
        daily_totals[key] = daily_totals.get(key, 0.0) + duration

    # Batch-fetch every Staff row this loop could need up front (by id and
    # by name, since daily_totals keys on whichever identifier a given
    # Attendance record has) instead of issuing one query per (date, staff)
    # entry below - avoids an N+1 query per iteration.
    staff_ids = {k for _, k in daily_totals.keys() if isinstance(k, int)}
    staff_names = {k for _, k in daily_totals.keys() if not isinstance(k, int)}
    staff_by_id = {}
    staff_by_name = {}
    if staff_ids:
        for s in db.query(models.Staff).filter(models.Staff.id.in_(staff_ids)).all():
            staff_by_id[s.id] = s
    if staff_names:
        for s in db.query(models.Staff).filter(models.Staff.name.in_(staff_names)).all():
            staff_by_name[s.name] = s

    shift_compliance: dict = {}
    for (date_str, staff_key), actual_hours in daily_totals.items():
        staff = (
            staff_by_id.get(staff_key)
            if isinstance(staff_key, int)
            else staff_by_name.get(staff_key)
        )
        expected_hours = staff.expected_shift_hours if staff else None
        if expected_hours is None:
            status = "no_shift_set"
            delta_hours = None
        else:
            delta_hours = round(actual_hours - expected_hours, 2)
            if abs(delta_hours) <= SHIFT_COMPLIANCE_TOLERANCE_HOURS:
                status = "on_time"
            elif delta_hours < 0:
                status = "under"
            else:
                status = "over"

        shift_compliance.setdefault(date_str, []).append({
            "staff_name": staff.name if staff else str(staff_key),
            "expected_hours": round(expected_hours, 2) if expected_hours is not None else None,
            "actual_hours": round(actual_hours, 2),
            "delta_hours": delta_hours,
            "status": status,
        })

    avg_shift_length = round(total_hours / len(records), 1) if records else 0.0
    system_alerts = db.query(models.SecurityAlert).filter(models.SecurityAlert.resolved == False).count()

    return {
        "summary": summary,
        "shift_compliance": shift_compliance,
        "stats": {
            "active_staff": len(active_staff),
            "avg_shift_length": avg_shift_length,
            "system_alerts": system_alerts,
            "ai_utilization": 92
        }
    }

@router.get("/events")
def get_recent_events(limit: int = 50, db: Session = Depends(get_db)):
    """
    Fetch the most recent system events, including Unknown Faces and Offline Alerts.
    """
    events = (
        db.query(models.SystemEvent)
        .order_by(models.SystemEvent.timestamp.desc())
        .limit(limit)
        .all()
    )
    return events


import psutil
import torch

@router.get("/dashboard")
def get_admin_dashboard(db: Session = Depends(get_db)):
    """
    Returns comprehensive data for the Super Admin Dashboard in a single API call.
    """
    # 1. System Health (Environment-agnostic)
    def get_service_metrics():
        import os
        import time
        procs_to_measure = []

        # 1. Backend process tree (FastAPI + AI Workers)
        try:
            parent = psutil.Process(os.getpid())
            procs_to_measure = [parent] + parent.children(recursive=True)
        except Exception:
            pass

        # 2. Frontend processes (Flutter/Dart/Medical Agent)
        try:
            for p in psutil.process_iter(['name', 'cmdline']):
                try:
                    name = (p.info.get('name') or '').lower()
                    cmd = ' '.join(p.info.get('cmdline') or []).lower()
                    if 'flutter' in name or 'dart' in name or 'medical_agent' in name or 'flutter' in cmd or 'dart' in cmd:
                        if p not in procs_to_measure:
                            procs_to_measure.append(p)
                except Exception:
                    pass
        except Exception:
            pass

        # Prime CPU measurement
        for p in procs_to_measure:
            try: p.cpu_percent(None)
            except Exception: pass

        time.sleep(0.1) # 100ms sample window

        total_cpu = 0.0
        total_ram = 0.0
        for p in procs_to_measure:
            try:
                total_cpu += p.cpu_percent(None)
                total_ram += p.memory_percent()
            except Exception:
                pass

        core_count = psutil.cpu_count() or 1
        # Process cpu_percent is per-core (e.g. 400% on 4 cores), normalize to 100%
        return min(total_cpu / core_count, 100.0), min(total_ram, 100.0)

    cpu_percent, ram_percent = get_service_metrics()

    # GPU Utilization (Compute)
    gpu_percent = 0.0
    try:
        import subprocess
        # Get actual compute utilization from nvidia-smi
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            gpu_percent = float(result.stdout.strip().split('\n')[0])
        elif torch.backends.mps.is_available():
            cameras_count = db.query(models.Camera).count()
            gpu_percent = min(15.0 * cameras_count + cpu_percent * 0.2, 95.0)
    except Exception:
        gpu_percent = min(cpu_percent * 0.8, 100.0)

    system_health = {
        "cpu_utilization": round(cpu_percent, 1),
        "gpu_utilization": round(gpu_percent, 1),
        "ram_utilization": round(ram_percent, 1),
        "active_node": "Node Alpha",
        "model_status": {
            "name": "Model X",
            "state": "ACTIVE",
            "progress": 94,
            "latency_ms": 12
        }
    }

    # 2. Departmental Resources
    # Group attendance by camera_name for today to determine load distribution
    today = datetime.date.today()
    attendances = db.query(models.Attendance).filter(models.Attendance.date == today).all()

    dept_counts = {}
    for att in attendances:
        cname = att.camera_name or "Unknown"
        dept_counts[cname] = dept_counts.get(cname, 0) + 1

    total_load = sum(dept_counts.values())
    departments = []
    if total_load > 0:
        for name, count in dept_counts.items():
            departments.append({
                "name": name,
                "percentage": int(round((count / total_load) * 100)),
                "raw_count": count
            })
    else:
        departments = []

    # 3. Patient Flow (24h)
    # We group attendance entry times in the last 24h into 4-hour buckets
    now = datetime.datetime.now(datetime.timezone.utc)
    # Convert naive now to aware if needed
    now = now.astimezone()

    # We'll create 7 data points (0, 4, 8, 12, 16, 20, 24)
    patient_flow_counts = {h: 0 for h in [0, 4, 8, 12, 16, 20, 24]}

    for att in attendances:
        if not att.entry_time:
            continue
        # Convert to local time if necessary, but here we can just use the hour
        hour = att.entry_time.hour
        # Find the closest 4-hour bucket
        bucket = (hour // 4) * 4
        patient_flow_counts[bucket] += 1

    patient_flow = [{"hour": k, "count": v} for k, v in sorted(patient_flow_counts.items())]

    # 4. Security Vault
    # Fetch latest 5 alerts
    alerts_query = db.query(models.SecurityAlert).order_by(models.SecurityAlert.timestamp.desc()).limit(5).all()
    security_vault = []
    for alert in alerts_query:
        import json
        snapshot_path = None
        staff_name = None
        if alert.details:
            try:
                details_json = json.loads(alert.details)
                snapshot_path = details_json.get("snapshot_path")
                staff_name = details_json.get("staff_name")
                if staff_name and staff_name.lower() == "unknown":
                    staff_name = None
            except Exception:
                pass

        security_vault.append({
            "id": alert.id,
            "timestamp": alert.timestamp.strftime("%H:%M:%S UTC") if alert.timestamp else "",
            "type": alert.rule_name or "Unknown Alert",
            "engine": "Auth-Shield AI",
            "risk": alert.severity.upper() if alert.severity else "ROUTINE",
            "resolved": alert.resolved,
            "snapshot_path": snapshot_path,
            "camera_name": alert.camera.name if alert.camera else None,
            "zone": alert.camera.location if alert.camera else None,
            "staff_name": staff_name,
        })

    if not security_vault:
        security_vault = [
             {"id": 1, "timestamp": "14:23:45 UTC", "type": "Restricted Access Attempt", "engine": "Bio-Metric Sentry V2", "risk": "CRITICAL", "resolved": False},
             {"id": 2, "timestamp": "14:18:12 UTC", "type": "Unusual Data Pattern", "engine": "Patient Health Monitor", "risk": "ELEVATED", "resolved": False},
             {"id": 3, "timestamp": "13:55:01 UTC", "type": "Credential Verification", "engine": "Auth-Shield AI", "risk": "ROUTINE", "resolved": True}
        ]

    return {
        "system_health": system_health,
        "department_resources": departments,
        "patient_flow": patient_flow,
        "security_vault": security_vault
    }
