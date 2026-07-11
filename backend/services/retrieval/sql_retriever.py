from sqlalchemy.orm import Session
from sqlalchemy import text
from typing import List, Dict, Any

class SQLRetriever:
    """
    Safely executes parameterized SQL templates.
    """
    def execute(self, db: Session, sql_template: str, params: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Executes a parameterized query safely and returns a list of dictionaries.
        """
        try:
            # We use ILIKE logic mapped properly for parameters where partial matching is needed
            # For exact matches, parameter should be passed directly
            processed_params = {}
            for k, v in params.items():
                # SQLAlchemy bind params can't have spaces (e.g. 'Patient Name' -> 'patient_name')
                safe_key = k.lower().replace(" ", "_")
                # If the string param is meant to be matched with ILIKE, we append % % if needed.
                processed_params[safe_key] = f"%{v}%" if isinstance(v, str) else v

            # Execute
            result_proxy = db.execute(text(sql_template), processed_params)
            rows = result_proxy.fetchall()
            
            # Convert to list of dicts
            result = []
            keys = result_proxy.keys()
            for row in rows:
                result.append(dict(zip(keys, row)))
            return result
        except Exception as e:
            print(f"[SQLRetriever] Execution Error: {e}")
            return []

sql_retriever = SQLRetriever()
