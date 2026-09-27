#!/usr/bin/env bash
# ZAP scans against the ephemeral stack from stack-up.sh (never a real
# environment — the API scan sends real attack payloads):
#   1. baseline  — passive spider of the Swagger UI
#   2. api       — active scan of every endpoint in the OpenAPI spec
#
# Policy (DevOps Master Guide A4): everything is WARN by default and runs
# with -I, so warnings never fail the build. Only rules promoted to FAIL in
# backend/zap/rules.tsv block. Reports land in $OUT_DIR for archiving.
#
# Required env: CI_ID, ZAP_IMAGE. Optional: OUT_DIR (default zap-reports).
set -euo pipefail
: "${CI_ID:?}" "${ZAP_IMAGE:?}"

OUT="${OUT_DIR:-zap-reports}"
NET="$CI_ID-net"
C="$CI_ID-zap"
RULES="backend/zap/rules.tsv"
TARGET="http://nest-1:3000"
mkdir -p "$OUT"

run_zap() {
  local name="$1" rc staging
  shift
  docker rm -f "$C" >/dev/null 2>&1 || true
  docker create --name "$C" --network "$NET" "$ZAP_IMAGE" "$@" >/dev/null

  # The image has no /zap/wrk and runs as uid 1000 (zap). Ship the rules
  # file in via a tar stream owned by 1000 so ZAP can write its reports
  # next to it — no bind mount, so this works from a containerised Jenkins
  # too (the host daemon can't see paths inside the Jenkins container).
  staging="$(mktemp -d)"
  mkdir "$staging/wrk"
  cp "$RULES" "$staging/wrk/rules.tsv"
  tar -C "$staging" --owner=1000 --group=1000 --numeric-owner -cf - wrk | docker cp -a - "$C:/zap/"
  rm -rf "$staging"

  set +e
  docker start -a "$C"
  rc=$?
  set -e
  docker cp "$C:/zap/wrk/." "$OUT/" >/dev/null 2>&1 || true
  docker rm -f "$C" >/dev/null 2>&1 || true

  # zap-*.py exit codes: 0 clean, 1 a FAIL rule fired, 2 WARN only
  # (suppressed by -I), 3 ZAP itself errored.
  case "$rc" in
    0|2) echo "ZAP $name: no FAIL-level alerts (rc=$rc)" ;;
    1)   echo "ZAP $name: FAIL-level alert(s) — see $OUT/$name.html" >&2; return 1 ;;
    *)   echo "ZAP $name: scanner error (rc=$rc)" >&2; return 1 ;;
  esac
}

status=0
run_zap baseline zap-baseline.py -t "$TARGET/api/docs" \
  -c rules.tsv -I -r baseline.html -J baseline.json || status=1
run_zap api zap-api-scan.py -t "$TARGET/api/docs-json" -f openapi \
  -c rules.tsv -I -r api.html -J api.json || status=1
exit "$status"
