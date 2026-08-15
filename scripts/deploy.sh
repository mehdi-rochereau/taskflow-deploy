#!/bin/bash
# ==============================================================
# deploy.sh — TaskFlow production deployment script
#
# Usage: ./scripts/deploy.sh
#
# Prerequisites:
#   - Docker and Docker Compose installed on the server
#   - .env file present at /opt/taskflow/.env
#   - GitHub Container Registry authentication configured
#
# What it does:
#   1. Pulls the latest images from GitHub Container Registry
#   2. Restarts the stack with zero-downtime strategy
#   3. Cleans up unused Docker images
# ==============================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────
DEPLOY_DIR="/opt/taskflow"
COMPOSE_FILE="$DEPLOY_DIR/docker-compose.yml"
LOG_FILE="$DEPLOY_DIR/deploy.log"

# ── Colors ─────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Logging ────────────────────────────────────────────────
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARN:${NC} $1" | tee -a "$LOG_FILE"
}

# ── Checks ─────────────────────────────────────────────────
log "Starting TaskFlow deployment..."

[ -f "$COMPOSE_FILE" ] || error "docker-compose.yml not found at $COMPOSE_FILE"
[ -f "$DEPLOY_DIR/.env" ] || error ".env file not found at $DEPLOY_DIR/.env"

# ── Pull latest images ─────────────────────────────────────
log "Pulling latest images from GitHub Container Registry..."
docker compose -f "$COMPOSE_FILE" --env-file "$DEPLOY_DIR/.env" pull

# ── Restart stack ──────────────────────────────────────────
log "Restarting TaskFlow stack..."
docker compose -f "$COMPOSE_FILE" --env-file "$DEPLOY_DIR/.env" up -d --remove-orphans

# ── Health check ───────────────────────────────────────────
log "Waiting for services to be healthy..."
sleep 10

API_STATUS=$(docker inspect --format='{{.State.Health.Status}}' taskflow-api 2>/dev/null || echo "unknown")

if [ "$API_STATUS" = "healthy" ]; then
    log "taskflow-api is healthy"
elif [ "$API_STATUS" = "starting" ]; then
    warn "taskflow-api is still starting — check logs if it fails"
else
    error "taskflow-api health check failed (status: $API_STATUS)"
fi

# ── Cleanup ────────────────────────────────────────────────
log "Cleaning up unused Docker images..."
docker image prune -f

log "Deployment completed successfully!"