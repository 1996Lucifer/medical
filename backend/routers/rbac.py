from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from database import get_db
import models

router = APIRouter(prefix="/api/rbac", tags=["rbac"])

class AssignRequest(BaseModel):
    source_type: str # "user" or "group"
    source_id: int
    target_type: str # "group" or "permission"
    target_id: int

class NodeCreateRequest(BaseModel):
    name: str
    description: str = ""

@router.get("/graph")
def get_rbac_graph(db: Session = Depends(get_db)):
    # Fetch all entities
    users = db.query(models.User).all()
    groups = db.query(models.RBACGroup).all()
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
def assign_rbac(req: AssignRequest, db: Session = Depends(get_db)):
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
def unassign_rbac(req: AssignRequest, db: Session = Depends(get_db)):
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
def create_group(req: NodeCreateRequest, db: Session = Depends(get_db)):
    if db.query(models.RBACGroup).filter(models.RBACGroup.name == req.name).first():
        raise HTTPException(400, "Group already exists")
    new_group = models.RBACGroup(name=req.name, description=req.description)
    db.add(new_group)
    db.commit()
    db.refresh(new_group)
    return {"status": "success", "id": new_group.id}

@router.post("/permissions")
def create_permission(req: NodeCreateRequest, db: Session = Depends(get_db)):
    if db.query(models.RBACPermission).filter(models.RBACPermission.name == req.name).first():
        raise HTTPException(400, "Permission already exists")
    new_perm = models.RBACPermission(name=req.name, description=req.description)
    db.add(new_perm)
    db.commit()
    db.refresh(new_perm)
    return {"status": "success", "id": new_perm.id}

@router.delete("/groups/{group_id}")
def delete_group(group_id: int, db: Session = Depends(get_db)):
    group = db.query(models.RBACGroup).get(group_id)
    if not group:
        raise HTTPException(404, "Group not found")
    db.delete(group)
    db.commit()
    return {"status": "success"}

@router.delete("/permissions/{permission_id}")
def delete_permission(permission_id: int, db: Session = Depends(get_db)):
    perm = db.query(models.RBACPermission).get(permission_id)
    if not perm:
        raise HTTPException(404, "Permission not found")
    db.delete(perm)
    db.commit()
    return {"status": "success"}
