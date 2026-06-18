#!/bin/bash

echo "Cleaning up any suspended processes on port 8000..."
# Find and kill any process using port 8000
lsof -t -i :8000 | xargs -I {} kill -9 {} 2>/dev/null

echo "Starting Uvicorn backend server..."
# Start the server (no --reload to prevent killing active camera streams)
./.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
