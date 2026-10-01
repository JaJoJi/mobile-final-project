#!/usr/bin/env bash
# Pull-based deploy on the university VM (#221). Jenkins only releases
# (pushes fiatthanapon/mobile-final-project:<commit> on main); this pulls
# that exact image and swaps it in:
#
#   1. pull the release image + pinned infra images
#   2. docker compose up -d (only changed containers restart)
#   3. wait for /health/ready through nginx (Postgres + Redis reachable)
#   4. healthy   -> record the tag as current
#      unhealthy -> redeploy the previous tag and exit 1
#
#   sudo auto-chess-deploy <tag>     e.g. d5ec4c4 (Jenkins build / Docker Hub)
#   sudo auto-chess-deploy --status  what's running
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$(readlink -f "$0")")/../../.." && pwd)
ENV_FILE=/etc/auto-chess/app.env
STATE_DIR=/var/lib/auto-chess
HEALTH_URL=${HEALTH_URL:-http://127.0.0.1/health/ready}
COMPOSE=(docker compose -f "$REPO_DIR/infra/uni-vm/app/compose.yml" --env-file "$ENV_FILE")

log() { echo "$(date '+%F %T') deploy: $*" | tee -a "$STATE_DIR/deploy.log"; }

[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
[[ -r $ENV_FILE ]] || { echo "missing $ENV_FILE (run site.yml)"; exit 1; }
if grep -q CHANGE_ME "$ENV_FILE"; then
  echo "fill in the CHANGE_ME secrets in $ENV_FILE first"; exit 1
fi
mkdir -p "$STATE_DIR"

prev=$(cat "$STATE_DIR/current_tag" 2>/dev/null || true)

if [[ ${1:-} == --status ]]; then
  echo "current tag: ${prev:-<none>}"
  IMAGE_TAG=${prev:-none} "${COMPOSE[@]}" ps
  exit 0
fi

TAG=${1:?usage: auto-chess-deploy <image-tag> | --status}
[[ $TAG =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "bad tag: $TAG"; exit 1; }

up() {
  IMAGE_TAG=$1 "${COMPOSE[@]}" pull --quiet
  IMAGE_TAG=$1 "${COMPOSE[@]}" up -d --remove-orphans
}

healthy() {
  local code
  for _ in $(seq 1 36); do          # up to 3 min (first start runs migrations)
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$HEALTH_URL" || true)
    [[ $code == 200 ]] && return 0
    sleep 5
  done
  return 1
}

log "deploying $TAG (previous: ${prev:-none})"
if up "$TAG" && healthy; then
  echo "$TAG" > "$STATE_DIR/current_tag"
  docker image prune -f >/dev/null 2>&1 || true
  log "OK -- $TAG is live"
  exit 0
fi

log "FAILED -- $TAG not healthy; nest logs:"
IMAGE_TAG=$TAG "${COMPOSE[@]}" logs --tail 30 nest-1 2>&1 | tee -a "$STATE_DIR/deploy.log" || true

if [[ -n $prev && $prev != "$TAG" ]]; then
  log "rolling back to $prev"
  if up "$prev" && healthy; then
    log "rolled back -- $prev is live again"
  else
    log "ROLLBACK FAILED -- check: docker compose ps / logs"
  fi
fi
exit 1
