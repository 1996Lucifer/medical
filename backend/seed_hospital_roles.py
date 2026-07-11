import sys
import os

# Add backend directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from database import engine, SessionLocal, Base
import models
import bcrypt

def get_password_hash(password: str) -> str:
    password_bytes = password.encode('utf-8')
    hashed_bytes = bcrypt.hashpw(password_bytes, bcrypt.gensalt())
    return hashed_bytes.decode('utf-8')

def seed_roles():
    # 1. Create tables if they don't exist
    Base.metadata.create_all(bind=engine)
    print("Executed Base.metadata.create_all().")
    
    db = SessionLocal()
    try:
        # 2. Define Permissions
        permissions_def = {
            "view_admin": "Access to Super Admin Dashboard",
            "view_consultation": "Access to Consultation Screen",
            "view_camera": "Access to AI Camera Screen",
            "view_analytics": "Access to Analytics Dashboard",
            "view_security": "Access to Security Dashboard",
            "view_agent": "Access to Medical Agent",
            "view_settings": "Access to System Settings"
        }
        
        db_perms = {}
        for p_name, p_desc in permissions_def.items():
            perm = db.query(models.RBACPermission).filter(models.RBACPermission.name == p_name).first()
            if not perm:
                perm = models.RBACPermission(name=p_name, description=p_desc)
                db.add(perm)
                db.commit()
                db.refresh(perm)
                print(f"Added permission: {p_name}")
            db_perms[p_name] = perm
            
        # 3. Define Roles (Groups) and their assigned permissions
        roles_def = {
            "Doctor": ["view_consultation", "view_agent"],
            "Nurse": ["view_consultation", "view_agent"],
            "Security": ["view_camera", "view_security"],
            "Analyst": ["view_analytics"],
            "Admin": ["view_settings"],
            "SuperAdmin": ["view_admin", "view_consultation", "view_camera", "view_analytics", "view_security", "view_agent", "view_settings"]
        }
        
        db_groups = {}
        for role_name, role_perms in roles_def.items():
            group = db.query(models.RBACGroup).filter(models.RBACGroup.name == role_name).first()
            if not group:
                group = models.RBACGroup(name=role_name, description=f"{role_name} Role")
                db.add(group)
                db.commit()
                db.refresh(group)
                print(f"Added group/role: {role_name}")
            
            # Map permissions
            for p_name in role_perms:
                perm = db_perms[p_name]
                if perm not in group.permissions:
                    group.permissions.append(perm)
            db.commit()
            db_groups[role_name] = group
            
        # 4. Create dummy users for each role
        users_def = {
            "doctor": "Doctor",
            "nurse": "Nurse",
            "security": "Security",
            "analyst": "Analyst",
            "admin": "Admin",
            "superadmin": "SuperAdmin"
        }
        
        for username, role_name in users_def.items():
            user = db.query(models.User).filter(models.User.username == username).first()
            if not user:
                # the role string column will be set to lower case of role_name for backwards compatibility
                user = models.User(
                    username=username,
                    hashed_password=get_password_hash(username), # password is same as username
                    role=username 
                )
                db.add(user)
                db.commit()
                db.refresh(user)
                print(f"Added test user: {username}")
                
            group = db_groups[role_name]
            if group not in user.groups:
                user.groups.append(group)
                db.commit()
                print(f"Assigned {username} to {role_name} group.")
                
        print("Hospital roles and users seeded successfully!")

    except Exception as e:
        print(f"Error seeding roles: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    seed_roles()
