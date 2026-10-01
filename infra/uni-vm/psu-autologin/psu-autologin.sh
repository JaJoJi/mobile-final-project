#!/usr/bin/env bash
# Keeps the university VM online: the PSU captive portal drops the
# internet session every so often, which would cut the VM off from
# Docker Hub, apt, etc. Run every minute by psu-autologin.timer:
#
#   online?  -> do nothing
#   offline? -> log in to the portal (same POST as psu_passport.bash),
#               then check again
#
# Credentials come from /etc/psu-autologin.env (root-only, 0600), never
# from this file or the command line. After repeated failures it backs
# off (2, 4, 8 ... 30 min) so a wrong password doesn't hammer the portal
# and lock the account.
#
# Manual run:  sudo psu-autologin            (check, log in if needed)
#              sudo psu-autologin --force    (log in even if online)
set -euo pipefail

ENV_FILE=/etc/psu-autologin.env
STATE_DIR=${STATE_DIRECTORY:-/var/lib/psu-autologin}
# Endpoints that answer HTTP 204 with an empty body. A captive portal
# intercepts plain HTTP and answers something else (200 page / 30x).
CHECK_URLS=(
  http://connectivitycheck.gstatic.com/generate_204
  http://cp.cloudflare.com/generate_204
)
MAX_BACKOFF_MIN=30

log() { echo "psu-autologin: $*"; }

# ── credentials ───────────────────────────────────────────────────────
if [[ -z ${PSU_USERNAME:-} || -z ${PSU_PASSWORD:-} ]]; then
  # Not started by systemd (which loads EnvironmentFile=): read it here.
  [[ -r $ENV_FILE ]] || { log "cannot read $ENV_FILE (run as root?)"; exit 1; }
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi
if [[ -z ${PSU_USERNAME:-} || -z ${PSU_PASSWORD:-} \
      || $PSU_USERNAME == CHANGE_ME || $PSU_PASSWORD == CHANGE_ME ]]; then
  log "fill in PSU_USERNAME / PSU_PASSWORD in $ENV_FILE first"
  exit 1
fi
# After the env file, so PSU_PORTAL_URL there can override it.
PORTAL_URL=${PSU_PORTAL_URL:-https://cp-xml-40g.psu.ac.th:6082/php/action_page.php}
perm=$(stat -c '%a %U' "$ENV_FILE" 2>/dev/null || echo "?")
if [[ $perm != "600 root" ]]; then
  log "refusing: $ENV_FILE must be owned by root with mode 600 (is: $perm)"
  exit 1
fi

# ── connectivity check ────────────────────────────────────────────────
online() {
  local url code
  for url in "${CHECK_URLS[@]}"; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" || true)
    [[ $code == 204 ]] && return 0
  done
  return 1
}

# ── backoff state ─────────────────────────────────────────────────────
mkdir -p "$STATE_DIR"
FAIL_FILE=$STATE_DIR/failures
failures=0; last=0
if [[ -r $FAIL_FILE ]]; then read -r failures last < "$FAIL_FILE" || true; fi
failures=${failures:-0}; last=${last:-0}

FORCE=false
[[ ${1:-} == --force ]] && FORCE=true

if ! $FORCE && online; then
  if (( failures > 0 )); then log "online again"; rm -f "$FAIL_FILE"; fi
  exit 0
fi

if ! $FORCE && (( failures >= 3 )); then
  wait_min=$(( 2 ** (failures - 2) ))
  (( wait_min > MAX_BACKOFF_MIN )) && wait_min=$MAX_BACKOFF_MIN
  if (( $(date +%s) - last < wait_min * 60 )); then
    exit 0    # still backing off; stay quiet in the journal
  fi
fi

# ── log in ────────────────────────────────────────────────────────────
# Username/password go to curl through 0600 temp files (@file), so they
# never appear in the process list (`ps` shows curl's arguments).
log "offline -- logging in to the portal as $PSU_USERNAME"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '%s' "$PSU_USERNAME" > "$tmp/u"
printf '%s' "$PSU_PASSWORD" > "$tmp/p"

http=$(curl -sS -o "$tmp/resp" -w '%{http_code}' --max-time 20 \
  --data-urlencode "username@$tmp/u" \
  --data-urlencode "password@$tmp/p" \
  --data "login=" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -X POST "$PORTAL_URL" || echo "000")

# The portal can take a moment to open the session.
for _ in 1 2 3; do
  sleep 2
  if online; then
    log "login OK (portal HTTP $http), internet is back"
    rm -f "$FAIL_FILE"
    exit 0
  fi
done

failures=$(( failures + 1 ))
echo "$failures $(date +%s)" > "$FAIL_FILE"
log "login FAILED (portal HTTP $http, attempt $failures) -- still offline"
log "portal said: $(tr -s '[:space:]' ' ' < "$tmp/resp" | sed 's/<[^>]*>//g' | cut -c1-200)"
exit 1
