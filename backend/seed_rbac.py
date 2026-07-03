import sys
import os

# Add backend directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from database import engine, SessionLocal, Base
import models
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def setup_rbac():
    # 1. Create tables if they don't exist
    Base.metadata.create_all(bind=engine)
    print("Executed Base.metadata.create_all().")
    
    db = SessionLocal()
    try:
        # 2. Seed Default Permissions
        perms = [
            {"name": "view_cameras", "description": "View live camera feeds"},
            {"name": "manage_staff", "description": "Add or remove staff"},
            {"name": "edit_rules", "description": "Create and manage AI security rules"},
            {"name": "view_reports", "description": "View medical reports"},
        ]
        
        db_perms = {}
        for p in perms:
            perm = db.query(models.RBACPermission).filter(models.RBACPermission.name == p["name"]).first()
            if not perm:
                perm = models.RBACPermission(name=p["name"], description=p["description"])
                db.add(perm)
                db.commit()
                db.refresh(perm)
                print(f"Added permission: {p['name']}")
            db_perms[p["name"]] = perm
            
        # 3. Seed Default Group
        admin_group = db.query(models.RBACGroup).filter(models.RBACGroup.name == "Administrators").first()
        if not admin_group:
            admin_group = models.RBACGroup(name="Administrators", description="Full access to all systems")
            db.add(admin_group)
            db.commit()
            db.refresh(admin_group)
            print("Added Administrators group.")
            
            # Map permissions to group
            for perm in db_perms.values():
                admin_group.permissions.append(perm)
            db.commit()
            print("Mapped all permissions to Administrators group.")
            
        # 4. Seed Default Admin User if missing
        admin_user = db.query(models.User).filter(models.User.username == "admin").first()
        if not admin_user:
            admin_user = models.User(
                username="admin",
                hashed_password=pwd_context.hash("admin"),
                role="admin"
            )
            db.add(admin_user)
            db.commit()
            db.refresh(admin_user)
            print("Added default 'admin' user.")
            
        # Ensure Admin is in Admin Group
        if admin_group not in admin_user.groups:
            admin_user.groups.append(admin_group)
            db.commit()
            print("Mapped 'admin' user to Administrators group.")
            
    except Exception as e:
        print(f"Error seeding RBAC: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    setup_rbac()
