# Hospital AI Assistant - Architecture & Development Notes

## Overview

This project is a local-first AI-powered hospital assistant designed to
combine structured database retrieval, semantic search, and multiple
LLMs.

## Architecture

``` text
User Query
    |
Intent Router (MiniLM)
    |
+-----------------------------+
| Medical      | General      |
| SQL          | SQL          |
| Vector       | Vector       |
| MedGemma     | Qwen3/Llama  |
+-----------------------------+
            |
      Final Response
```

## Models

-   Medical: MedGemma 4B GGUF (Q4)
-   General: Qwen3 4B GGUF
-   Router: all-MiniLM-L6-v2
-   Embeddings: BAAI/bge-small-en-v1.5

## Retrieval Order

1.  Intent Classification
2.  SQL Retrieval
3.  Vector Retrieval
4.  LLM Reasoning
5.  Response

## Existing Modules

-   Equipment
-   Cameras
-   Security
-   Patients
-   Consultations
-   Medical Reports
-   Staff
-   Attendance
-   RBAC

## New Tables

### knowledge_documents

Store manuals, SOPs, WHO guidelines, PDFs and embeddings.

### document_chunks

Store chunk text with embeddings.

### medical_faq

Frequently asked questions with embeddings.

### conversation_history

Conversation memory.

### llm_audit_log

Prompt, context, model, latency, response and confidence.

## Tech Stack

-   FastAPI
-   PostgreSQL
-   pgvector
-   SQLAlchemy
-   Ollama / llama.cpp
-   Redis (optional)

## Principles

-   Database first
-   SQL before vector search
-   Vector search before LLM
-   LLM for reasoning only
-   Ground responses with retrieved context
-   Log all model activity
-   Fail gracefully: If context cannot be found, the LLM should state it does not know rather than guessing

## Security & Privacy

-   **Data Anonymization**: Patient Identifiable Information (PII) should be scrubbed before sending context to the LLM.
-   **Local Governance**: Inference is local; patient data never leaves the hospital network, aiding in HIPAA/GDPR compliance.
-   **Role-Based Access**: The RBAC module ensures users only retrieve context they are authorized to view.

## Future

-   OCR
-   Voice assistant
-   Medical image analysis
-   Drug interaction checker
-   Equipment identification
-   Offline support
-   Multi-language
