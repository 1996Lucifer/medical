"""drop knowledge_documents/document_chunks/medical_faq/llm_audit_log - confirmed zero usage anywhere in the codebase (audit, 2026-09-13)

Revision ID: 0007_drop_dead_tables
Revises: 0006_merge_hospital_site_config
Create Date: 2026-09-13

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from pgvector.sqlalchemy import Vector

# revision identifiers, used by Alembic.
revision: str = "0007_drop_dead_tables"
down_revision: Union[str, Sequence[str], None] = "0006_merge_hospital_site_config"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_table("document_chunks")
    op.drop_table("knowledge_documents")
    op.drop_table("medical_faq")
    op.drop_table("llm_audit_log")


def downgrade() -> None:
    op.create_table(
        "knowledge_documents",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column("title", sa.String(), nullable=False),
        sa.Column("document_type", sa.String(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now()
        ),
    )
    op.create_table(
        "document_chunks",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column(
            "document_id", sa.Integer(), sa.ForeignKey("knowledge_documents.id"),
            nullable=False,
        ),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("embedding", Vector(512), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now()
        ),
    )
    op.create_table(
        "medical_faq",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column("question", sa.String(), nullable=False),
        sa.Column("answer", sa.Text(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now()
        ),
    )
    op.create_table(
        "llm_audit_log",
        sa.Column("id", sa.Integer(), primary_key=True, index=True),
        sa.Column("session_id", sa.String(), index=True, nullable=True),
        sa.Column("prompt", sa.Text(), nullable=True),
        sa.Column("context_used", sa.Text(), nullable=True),
        sa.Column("retrieved_rows", sa.Integer(), nullable=True),
        sa.Column("model_used", sa.String(), nullable=True),
        sa.Column("response", sa.Text(), nullable=True),
        sa.Column("confidence", sa.Float(), nullable=True),
        sa.Column("latency_ms", sa.Float(), nullable=True),
        sa.Column("token_usage", sa.Integer(), nullable=True),
        sa.Column(
            "timestamp", sa.DateTime(timezone=True), server_default=sa.func.now()
        ),
    )
