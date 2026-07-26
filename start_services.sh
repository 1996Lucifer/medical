#!/bin/bash
set -e

echo "=== Starting Medial-Agent Container Services ==="

if [ -f "/workspace/backend/.env" ]; then
    set -a
    source /workspace/backend/.env
    set +a
fi
export DATABASE_URL="${DATABASE_URL:-postgresql://postgres:postgres@medical-db:5432/medical_agent}"

echo "Database URL configured: $DATABASE_URL"

# 1. Start Python FastAPI Backend Server
echo "Starting Python FastAPI Backend on port 8000..."
if [ -d "/workspace/backend" ]; then
    (
        cd /workspace/backend
        python3 -m uvicorn main:app --host 0.0.0.0 --port 8000
    ) >> /workspace/backend/uvicorn.log 2>&1 &
    BACKEND_PID=$!
else
    echo "Warning: /workspace/backend not found!"
fi

# 2. Build and Serve Flutter Web App
echo "Building Flutter Web Application..."
if [ -d "/workspace/flutter_source" ]; then
    (
        cd /workspace/flutter_source
        flutter pub get
        flutter build web --release
    )
    echo "Serving Flutter Web Application on port 8080..."
    python3 -m http.server 8080 --directory /workspace/flutter_source/build/web &
    FLUTTER_PID=$!
else
    echo "Warning: /workspace/flutter_source not found!"
fi

echo "Medial-Agent services running:"
echo " - Python Backend API: http://localhost:8000"
echo " - Flutter Web App:    http://localhost:8080"

# Keep container alive and handle shutdown signals
trap "kill ${BACKEND_PID:-} ${FLUTTER_PID:-} 2>/dev/null; exit 0" SIGINT SIGTERM
wait -n 2>/dev/null || tail -f /dev/null
