"""fix agent_memory.embedding vector dimension (512 -> 384)

The column was declared as vector(512) ("Assuming 512 for our embedding
model") but the embedding model actually used to populate it
(all-MiniLM-L6-v2, in services/retrieval/vector_retriever.py) produces
384-dim vectors. pgvector enforces the declared dimension on every
read/write, so every insert and similarity query against this column has
been failing silently (caught by a bare except in memory_extractor.py and
workflow_engine.py) - long-term agent memory has never actually persisted
anything. Table is empty in every environment this was checked against, so
no data migration is needed, just the type fix.

Revision ID: 0003_fix_agent_memory_dim
Revises: 0002_staff_category
Create Date: 2026-09-08

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0003_fix_agent_memory_dim"
down_revision: Union[str, Sequence[str], None] = "0002_staff_category"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE agent_memory ALTER COLUMN embedding TYPE vector(384)"
    )


def downgrade() -> None:
    op.execute(
        "ALTER TABLE agent_memory ALTER COLUMN embedding TYPE vector(512)"
    )
