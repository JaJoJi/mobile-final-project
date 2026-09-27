#!/usr/bin/env bash
# Run Azure CLI / Ansible from the pinned toolbox image (Dockerfile here).
# Ansible's controller can't run on native Windows, so everyone uses this.
#
#   ./run.sh az login --use-device-code          # once; kept in a docker volume
#   ./run.sh ansible-playbook provision.yml -e @vars.yml
#   ./run.sh ansible-playbook jenkins-host.yml
#
# SSH_KEY (default ~/.ssh/id_ed25519) is the key pair used for the VM. Only
# that pair is mounted, read-only, and copied in with 0600 perms (Windows
# mounts show up as 0777, which ssh refuses).
set -euo pipefail
cd "$(dirname "$0")"

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
[ -f "$SSH_KEY" ] && [ -f "$SSH_KEY.pub" ] || { echo "SSH key pair not found: $SSH_KEY(.pub) -- set SSH_KEY" >&2; exit 1; }

REPO="$(cd ../.. && pwd)"
KEY_DIR="$(cd "$(dirname "$SSH_KEY")" && pwd)"
KEY_NAME="$(basename "$SSH_KEY")"
# Git Bash on Windows: hand docker Windows-style paths, stop MSYS rewriting.
if command -v cygpath >/dev/null 2>&1; then
  REPO="$(cygpath -w "$REPO")"; KEY_DIR="$(cygpath -w "$KEY_DIR")"
  export MSYS_NO_PATHCONV=1
fi

docker build -q -t mfp-infra:local . >/dev/null

TTY=(-i); [ -t 0 ] && [ -t 1 ] && TTY=(-it)
exec docker run --rm "${TTY[@]}" \
  -v mfp-azure-cli:/root/.azure \
  -v "$REPO:/work" \
  -v "$KEY_DIR/$KEY_NAME:/keys-ro/id:ro" \
  -v "$KEY_DIR/$KEY_NAME.pub:/keys-ro/id.pub:ro" \
  mfp-infra:local \
  sh -c 'mkdir -p /keys /root/.ssh && cp /keys-ro/id /keys-ro/id.pub /keys/ && chmod 600 /keys/id \
         && printf "Host *\n  IdentityFile /keys/id\n" > /root/.ssh/config && exec "$@"' -- "$@"
