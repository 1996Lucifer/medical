#!/bin/bash
# ==============================================================================
# Setup Command Audit Log & Automator for Container: medial-agent
# Created: 2026-07-26
# Target Workspace: /home/dj/Projects/medical-agent
# ==============================================================================

set -e

# File path for logging execution output
LOG_FILE="/home/dj/Projects/medical-agent/setup_execution.log"
exec > >(tee -i "$LOG_FILE") 2>&1

echo "=== [STEP 1] Create project directory ==="
echo "Command: mkdir -p /home/dj/Projects/medical-agent"
mkdir -p /home/dj/Projects/medical-agent

echo "=== [STEP 2] Clone repository via SSH ==="
echo "Command: git clone git@github.com:1996Lucifer/medical.git /home/dj/Projects/medical-agent"
if [ ! -d "/home/dj/Projects/medical-agent/.git" ]; then
    git clone git@github.com:1996Lucifer/medical.git /home/dj/Projects/medical-agent
else
    echo "Repository already cloned."
fi

cd /home/dj/Projects/medical-agent

echo "=== [STEP 3] Make scripts executable ==="
echo "Command: chmod +x start_services.sh run_schema.sh setup_commands.sh"
chmod +x start_services.sh run_schema.sh setup_commands.sh

echo "=== [STEP 4] Allow local root GUI access to X11 display ==="
echo "Command: xhost +local:root || true"
xhost +local:root 2>/dev/null || echo "xhost permission skipped or not in X11 session"

echo "=== [STEP 5] Build Docker container image (medial-agent) ==="
echo "Command: docker compose build"
docker compose build

echo "=== [STEP 6] Start medical-db and medial-agent containers in background ==="
echo "Command: docker compose up -d"
docker compose up -d

echo "=== [STEP 7] Run schema.sql against PostgreSQL database ==="
echo "Command: ./run_schema.sh"
./run_schema.sh

echo "=== [STEP 8] Verify running container status ==="
echo "Command: docker ps"
docker ps

echo "=== [STEP 9] Check initial container logs ==="
echo "Command: docker logs --tail 30 medial-agent"
docker logs --tail 30 medial-agent || true

echo "=== Setup completed successfully! ==="
