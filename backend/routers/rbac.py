from typing import List

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session, selectinload
from database import get_db
import models
from routers.auth import get_current_user, has_permission

router = APIRouter(prefix="/api/rbac", tags=["rbac"])

# Separate router (same path prefix) mounted in main.py with plain auth only
# - the main `router` above is mounted with a router-level "manage_rbac"
# permission requirement covering every route on it, which is correct for
# actually editing the permission graph but wrong for this one read-only
# endpoint: any authenticated staff member needs it just to see the staff
# category dropdown / People Directory filter chips, not only RBAC admins.
public_router = APIRouter(prefix="/api/rbac", tags=["rbac"])


class RBACGroupSummary(BaseModel):
    id: int
    name: str
    model_config = ConfigDict(from_attributes=True)


@public_router.get("/groups", response_model=List[RBACGroupSummary])
def list_rbac_groups(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Just the group NAMES (no permissions/assignments - see /graph below for
    the full admin-only picture), open to any authenticated user since a
    role name isn't sensitive on its own. This is the single source of
    truth for "what are the real configured staff categories" - used by
    the staff-registration category dropdown and the People Directory's
    category filter chips, both of which previously had their own
    hand-maintained lists that had drifted out of sync with actual RBAC
    groups (found live: "Medical Staff" showed up as a directory filter
    chip and a selectable category despite never being a real RBACGroup -
    just leftover default placeholder text from the old hardcoded lists).

    Hierarchy-scoped: a group only appears here if the caller already holds
    every permission that group carries. Without this, any user with
    "manage_staff" - not necessarily an RBAC admin - could see (and, via
    the staff category dropdown, effectively assign) roles like SuperAdmin
    that grant permissions far beyond their own. Superadmin bypasses this
    (has_permission's own rule), so still sees every group.
    """
    groups = db.query(models.RBACGroup).order_by(models.RBACGroup.name).all()
    return [
        g
        for g in groups
        if all(has_permission(current_user, p.name) for p in g.permissions)
    ]


def _require_rbac_admin(current_user: models.User = Depends(get_current_user)) -> models.User:
    """
    Every endpoint in this router can grant or revoke any permission for any
    user or group — including granting someone superadmin-equivalent access.
    None of these endpoints previously required authentication at all (no
    Depends(get_current_user)), so anyone who could reach the API could
    rewrite the entire permission graph. Restricting to admin/superadmin
    matches the access level already used for other privileged actions
    (e.g. patients.py, staff.py create-login).
    """
    if current_user.role not in ("admin", "superadmin"):
        raise HTTPException(status_code=403, detail="You do not have access to RBAC administration.")
    return current_user


class AssignRequest(BaseModel):
    source_type: str # "user" or "group"
    source_id: int
    target_type: str # "group" or "permission"
    target_id: int

class NodeCreateRequest(BaseModel):
    name: str
    description: str = ""

@router.get("/graph")
def get_rbac_graph(db: Session = Depends(get_db), _admin: models.User = Depends(_require_rbac_admin)):
    # Fetch all entities. selectinload() batches the many-to-many
    # collections (groups/direct_permissions/permissions) into one extra
    # query per relationship instead of the loop below lazy-loading each
    # user's/group's collection with its own query (N+1).
    users = db.query(models.User).options(
        selectinload(models.User.groups),
        selectinload(models.User.direct_permissions),
    ).all()
    groups = db.query(models.RBACGroup).options(
        selectinload(models.RBACGroup.permissions),
    ).all()
    permissions = db.query(models.RBACPermission).all()
    
    nodes = []
    edges = []
    
    for u in users:
        nodes.append({"id": f"user_{u.id}", "type": "user", "label": u.username})
        for g in u.groups:
            edges.append({"source": f"user_{u.id}", "target": f"group_{g.id}"})
        for p in u.direct_permissions:
            edges.append({"source": f"user_{u.id}", "target": f"perm_{p.id}"})
            
    for g in groups:
        nodes.append({"id": f"group_{g.id}", "type": "group", "label": g.name})
        for p in g.permissions:
            edges.append({"source": f"group_{g.id}", "target": f"perm_{p.id}"})
            
    for p in permissions:
        nodes.append({"id": f"perm_{p.id}", "type": "permission", "label": p.name})
        
    return {"nodes": nodes, "edges": edges}

@router.post("/assign")
def assign_rbac(req: AssignRequest, db: Session = Depends(get_db), _admin: models.User = Depends(_require_rbac_admin)):
    if req.source_type == "user" and req.target_type == "group":
        user = db.query(models.User).get(req.source_id)
        group = db.query(models.RBACGroup).get(req.target_id)
        if user and group and group not in user.groups:
            user.groups.append(group)
            
    elif req.source_type == "user" and req.target_type == "perm":
        user = db.query(models.User).get(req.source_id)
        perm = db.query(models.RBACPermission).get(req.target_id)
        if user and perm and perm not in user.direct_permissions:
            user.direct_permissions.append(perm)
            
    elif req.source_type == "group" and req.target_type == "perm":
        group = db.query(models.RBACGroup).get(req.source_id)
        perm = db.query(models.RBACPermission).get(req.target_id)
        if group and perm and perm not in group.permissions:
            group.permissions.append(perm)
            
    else:
        raise HTTPException(400, "Invalid connection types")
        
    db.commit()
    return {"status": "success"}

@router.post("/unassign")
def unassign_rbac(req: AssignRequest, db: Session = Depends(get_db), _admin: models.User = Depends(_require_rbac_admin)):
    if req.source_type == "user" and req.target_type == "group":
        user = db.query(models.User).get(req.source_id)
        group = db.query(models.RBACGroup).get(req.target_id)
        if user and group and group in user.groups:
            user.groups.remove(group)
            
    elif req.source_type == "user" and req.target_type == "perm":
        user = db.query(models.User).get(req.source_id)
        perm = db.query(models.RBACPermission).get(req.target_id)
        if user and perm and perm in user.direct_permissions:
            user.direct_permissions.remove(perm)
            
    elif req.source_type == "group" and req.target_type == "perm":
        group = db.query(models.RBACGroup).get(req.source_id)
        perm = db.query(models.RBACPermission).get(req.target_id)
        if group and perm and perm in group.permissions:
            group.permissions.remove(perm)
            
    else:
        raise HTTPException(400, "Invalid connection types")
        
    db.commit()
    return {"status": "success"}

@router.post("/groups")
def create_group(req: NodeCreateRequest, db: Session = Depends(get_db), _admin: models.User = Depends(_require_rbac_admin)):
    if db.query(models.RBACGroup).filter(models.RBACGroup.name == req.name).first():
        raise HTTPException(400, "Group already exists")
    new_group = models.RBACGroup(name=req.name, description=req.description)
    db.add(new_group)
    db.commit()
    db.refresh(new_group)
    return {"status": "success", "id": new_group.id}

@router.post("/permissions")
def create_permission(req: NodeCreateRequest, db: Session = Depends(get_db), _admin: models.User = Depends(_require_rbac_admin)):
    if db.query(models.RBACPermission).filter(models.RBACPermission.name == req.name).first():
        raise HTTPException(400, "Permission already exists")
    new_perm = models.RBACPermission(name=req.name, description=req.description)
    db.add(new_perm)
    db.commit()
    db.refresh(new_perm)
    return {"status": "success", "id": new_perm.id}

@router.delete("/groups/{group_id}")
def delete_group(group_id: int, db: Session = Depends(get_db), _admin: models.User = Depends(_require_rbac_admin)):
    group = db.query(models.RBACGroup).get(group_id)
    if not group:
        raise HTTPException(404, "Group not found")
    db.delete(group)
    db.commit()
    return {"status": "success"}

@router.delete("/permissions/{permission_id}")
def delete_permission(permission_id: int, db: Session = Depends(get_db), _admin: models.User = Depends(_require_rbac_admin)):
    perm = db.query(models.RBACPermission).get(permission_id)
    if not perm:
        raise HTTPException(404, "Permission not found")
    db.delete(perm)
    db.commit()
    return {"status": "success"}
