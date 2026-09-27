#!/usr/bin/env bash
# Boot a throwaway copy of the backend stack on its own docker network:
# Postgres + Redis + 3 Nest instances from the image Jenkins just built
# (same topology as docker-compose.yml's nest-1/2/3). Used by the
# integration smoke suite and the ZAP scan, torn down by stack-down.sh.
#
# No host ports and no bind mounts — everything is reached by container
# name on "$CI_ID-net", so this works the same whether Jenkins runs
# natively on the VM or inside a container next to the host's daemon.
#
# Required env: CI_ID (unique per build), IMAGE (backend image:tag),
#               PG_IMAGE, REDIS_IMAGE (pinned, set by the Jenkinsfile).
set -euo pipefail
: "${CI_ID:?}" "${IMAGE:?}" "${PG_IMAGE:?}" "${REDIS_IMAGE:?}"

NET="$CI_ID-net"

wait_for() {
  local what="$1" tries="$2"; shift 2
  for _ in $(seq 1 "$tries"); do
    if "$@" >/dev/null 2>&1; then echo "$what ready"; return 0; fi
    sleep 1
  done
  echo "$what not ready after ${tries}s" >&2
  return 1
}

# Idempotent: a re-run of the same build id must not collide with leftovers.
"$(dirname "$0")/stack-down.sh" >/dev/null 2>&1 || true
docker network create "$NET" >/dev/null

docker run -d --name "$CI_ID-pg" --network "$NET" --network-alias postgres \
  -e POSTGRES_USER=ci -e POSTGRES_PASSWORD=ci -e POSTGRES_DB=auto_chess \
  "$PG_IMAGE" >/dev/null
docker run -d --name "$CI_ID-redis" --network "$NET" --network-alias redis \
  "$REDIS_IMAGE" >/dev/null

# -h 127.0.0.1 = TCP: the entrypoint's init-phase server only listens on
# the unix socket, so a socket check would pass before Postgres is really up.
wait_for postgres 60 docker exec "$CI_ID-pg" pg_isready -h 127.0.0.1 -U ci -d auto_chess
wait_for redis 30 docker exec "$CI_ID-redis" redis-cli ping

# Fresh random secret per build — nothing to allowlist in gitleaks, and
# no two builds share a signing key.
JWT_SECRET="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"

start_nest() {
  local n="$1" migrate="$2"
  docker run -d --name "$CI_ID-nest-$n" --network "$NET" --network-alias "nest-$n" \
    -e NODE_ENV=production -e HOSTNAME="nest-$n" -e NEST_PORT=3000 \
    -e RUN_MIGRATIONS="$migrate" \
    -e DATABASE_URL=postgres://ci:ci@postgres:5432/auto_chess \
    -e REDIS_URL=redis://redis:6379 \
    -e JWT_SECRET="$JWT_SECRET" -e JWT_ACCESS_TTL=7d -e JWT_REFRESH_TTL=30d \
    "$IMAGE" >/dev/null
}

nest_ready() {
  # 127.0.0.1, not localhost: alpine resolves localhost to ::1 first and
  # Nest listens on 0.0.0.0 (IPv4) only.
  local n="$1"
  if ! wait_for "nest-$n" 60 docker exec "$CI_ID-nest-$n" wget -qO- http://127.0.0.1:3000/health/ready; then
    docker logs --tail 80 "$CI_ID-nest-$n" >&2 || true
    return 1
  fi
}

# nest-1 runs migrations; the other two start once the schema exists.
start_nest 1 true
nest_ready 1
start_nest 2 false
start_nest 3 false
nest_ready 2
nest_ready 3
