import sys
import os

# Add backend directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from database import engine, SessionLocal, Base
import models

def setup_db():
    Base.metadata.create_all(bind=engine)
    print("Executed Base.metadata.create_all().")

def add_rule():
    db = SessionLocal()
    # Check if rule exists
    existing = db.query(models.SecurityRule).filter(models.SecurityRule.target_area == "ICU").first()
    if not existing:
        rule = models.SecurityRule(
            target_area="ICU",
            rule_text="All staff entering the ICU must wear medical gloves.",
            is_active=True
        )
        db.add(rule)
        db.commit()
        print("Added dynamic rule: All staff entering the ICU must wear medical gloves.")
    else:
        print("Rule already exists.")
    db.close()

if __name__ == "__main__":
    setup_db()
    add_rule()
