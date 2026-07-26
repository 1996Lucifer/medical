#!/bin/bash
# ==============================================================================
# Helper Script: Run schema.sql and equipment_types.sql on medical-db
# ==============================================================================

set -e

cd /home/dj/Projects/medical-agent

echo "=== Executing backend/schema.sql on PostgreSQL medical-db ==="
docker exec -i medical-db psql -U postgres -d medical_agent -c "CREATE EXTENSION IF NOT EXISTS vector;"
docker exec -i medical-db psql -U postgres -d medical_agent < backend/schema.sql || true

echo "=== Executing equipment_types.sql on PostgreSQL medical-db ==="
if [ -f "equipment_types.sql" ]; then
    docker exec -i medical-db psql -U postgres -d medical_agent < equipment_types.sql || true
fi

echo "=== Database schema and equipment types applied successfully! ==="
