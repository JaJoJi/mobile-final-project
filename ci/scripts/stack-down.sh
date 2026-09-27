#!/usr/bin/env bash
# Tear down everything stack-up.sh / zap-scan.sh created for this build.
# Always exits 0 — it runs from `post { always }` and on re-runs.
: "${CI_ID:?}"

if [ -n "${LOG_DIR:-}" ]; then
  mkdir -p "$LOG_DIR"
  for n in 1 2 3; do
    docker logs "$CI_ID-nest-$n" >"$LOG_DIR/nest-$n.log" 2>&1 || true
  done
fi

docker rm -f "$CI_ID-zap" "$CI_ID-nest-1" "$CI_ID-nest-2" "$CI_ID-nest-3" \
  "$CI_ID-redis" "$CI_ID-pg" >/dev/null 2>&1 || true
docker network rm "$CI_ID-net" >/dev/null 2>&1 || true
exit 0
