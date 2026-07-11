import os
import sys

# Add parent directory to path to allow importing models and database
sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from database import engine
from sqlalchemy import inspect

class SchemaCache:
    """
    Loads database schema during startup and stores it in memory.
    Useful for future modules that need database context.
    """
    def __init__(self):
        self.tables = {}
        self.load_schema()

    def load_schema(self):
        """Loads tables and columns from the database engine."""
        try:
            inspector = inspect(engine)
            for table_name in inspector.get_table_names():
                columns = [col['name'] for col in inspector.get_columns(table_name)]
                self.tables[table_name] = columns
            print(f"[SchemaCache] Successfully loaded {len(self.tables)} tables.")
        except Exception as e:
            print(f"[SchemaCache] Warning: Could not load schema from database: {e}")

    def get_table_schema(self, table_name: str) -> list[str]:
        """Returns the list of columns for a given table."""
        return self.tables.get(table_name, [])

    def get_all_tables(self) -> list[str]:
        """Returns a list of all loaded table names."""
        return list(self.tables.keys())

# Singleton instance
schema_cache = SchemaCache()
