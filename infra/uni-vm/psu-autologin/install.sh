#!/usr/bin/env bash
# Installs the PSU portal auto-login on the university VM. Idempotent;
# re-run after pulling changes. Never overwrites an existing
# /etc/psu-autologin.env (your credentials).
#
#   sudo ./install.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
cd "$(dirname "$0")"

install -m 0755 psu-autologin.sh /usr/local/bin/psu-autologin
install -m 0644 psu-autologin.service psu-autologin.timer /etc/systemd/system/

if [[ ! -e /etc/psu-autologin.env ]]; then
  install -m 0600 -o root -g root psu-autologin.env.example /etc/psu-autologin.env
  created=true
else
  chown root:root /etc/psu-autologin.env
  chmod 0600 /etc/psu-autologin.env
  created=false
fi

systemctl daemon-reload
systemctl enable --now psu-autologin.timer

echo
if $created; then
  echo "Created /etc/psu-autologin.env -- put the PSU username/password in it:"
  echo "  sudo nano /etc/psu-autologin.env"
  echo "then test once:"
fi
echo "  sudo systemctl start psu-autologin.service && journalctl -u psu-autologin -n 20 --no-pager"
echo "Timer status:  systemctl list-timers psu-autologin.timer"
