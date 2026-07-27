#!/bin/bash
set -e

echo "=== Starting Medial-Agent Container Services ==="

if [ -f "/workspace/backend/.env" ]; then
    set -a
    source /workspace/backend/.env
    set +a
fi
# Inside Docker with network_mode: host, we must connect to the host's port 5433
if [ -f /.dockerenv ] || [ -f /proc/1/cgroup ]; then
    export DOCKER_CONTAINER=1
    export DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:5433/medical_agent"
else
    export DATABASE_URL="${DATABASE_URL:-postgresql://postgres:postgres@localhost:5433/medical_agent}"
fi

echo "Database URL configured: $DATABASE_URL"

# 1. Start Python FastAPI Backend Server
echo "Starting Python FastAPI Backend on port 8000..."
if [ -d "/workspace/backend" ]; then
    (
        cd /workspace/backend
        python3 -m uvicorn main:app --host 0.0.0.0 --port 8000
    ) &
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
