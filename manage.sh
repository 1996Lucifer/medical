#!/bin/bash
# ==============================================================================
# All-in-One Management Script for Medical Agent Platform
# ==============================================================================

set -e
PROJECT_DIR="/home/dj/Projects/medical-agent"
cd "$PROJECT_DIR"

usage() {
    echo "Usage: ./manage.sh [command]"
    echo ""
    echo "Commands:"
    echo "  setup         Full automated build, setup, and start"
    echo "  schema        Run database schema & equipment types on PostgreSQL"
    echo "  restart       Restart medical-db and medial-agent containers"
    echo "  start         Start docker containers"
    echo "  stop          Stop docker containers"
    echo "  status        Check container and HTTP service status"
    echo "  logs          View live logs of medial-agent container"
    echo "  db-shell      Open interactive psql shell inside PostgreSQL database"
    echo ""
}

case "${1:-}" in
    setup)
        echo "=== [1/4] Making scripts executable ==="
        chmod +x start_services.sh run_schema.sh setup_commands.sh manage.sh 2>/dev/null || true

        echo "=== [2/4] Building Docker container images ==="
        docker compose build

        echo "=== [3/4] Starting containers ==="
        docker compose up -d

        echo "=== [4/4] Applying database schema ==="
        ./run_schema.sh

        echo ""
        echo "=== Setup Complete! ==="
        docker ps --filter "name=medial-agent" --filter "name=medical-db"
        ;;

    schema)
        echo "=== Running Database Schema & Equipment Types ==="
        ./run_schema.sh
        ;;

    restart)
        echo "=== Restarting Docker Containers ==="
        docker compose restart
        echo "Containers restarted successfully."
        ;;

    start)
        echo "=== Starting Docker Containers ==="
        docker compose up -d
        ;;

    stop)
        echo "=== Stopping Docker Containers ==="
        docker compose stop
        ;;

    status)
        echo "=== Container Status ==="
        docker ps --filter "name=medial-agent" --filter "name=medical-db"
        echo ""
        echo "=== Endpoint Health Checks ==="
        echo -n "Python Backend API (http://localhost:8000/docs): "
        curl -sI http://localhost:8000/docs | head -n 1 || echo "Not responding"
        echo -n "Flutter Web App    (http://localhost:8080):      "
        curl -sI http://localhost:8080 | head -n 1 || echo "Not responding"
        ;;

    logs)
        echo "=== Streaming Logs for medial-agent ==="
        docker logs -f medial-agent
        ;;

    db-shell)
        echo "=== Opening PostgreSQL Shell ==="
        docker exec -it medical-db psql -U postgres -d medical_agent
        ;;

    *)
        usage
        ;;
esac
