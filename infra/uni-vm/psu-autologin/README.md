# PSU portal auto-login (university VM)

The campus network drops the VM's internet session every so often until
someone logs in to the PSU captive portal again. Without internet the VM
can't pull images from Docker Hub, update packages or ship monitoring
data. This keeps it online on its own.

## How it works

A systemd timer runs `psu-autologin` every minute:

1. **Online?** It fetches `generate_204` from Google/Cloudflare. A real
   `204` means online, so it does nothing. A captive portal answers
   something else.
2. **Offline:** it sends the same POST as `psu_passport.bash`
   (`username`, `password`, `login=`) to
   `https://cp-xml-40g.psu.ac.th:6082/php/action_page.php`, then checks
   again.
3. **Still failing (wrong password, portal down):** after 3 failures it
   backs off 2 → 4 → 8 … max 30 min between tries, so it doesn't hammer
   the portal and get the account locked.

Credentials live only in `/etc/psu-autologin.env` (root:root, `0600`).
The script refuses to run if that file is readable by anyone else. It
passes them to curl through temp files, never as command-line arguments
(those show up in `ps`).

## Install (on the VM)

```bash
git clone https://github.com/JaJoJi/mobile-final-project.git   # or git pull
cd mobile-final-project/infra/uni-vm/psu-autologin
sudo ./install.sh
sudo nano /etc/psu-autologin.env        # PSU_USERNAME / PSU_PASSWORD (keep the quotes)
sudo systemctl start psu-autologin.service
journalctl -u psu-autologin -n 20 --no-pager
```

## Day to day

| What | Command |
|---|---|
| Logs (drops, logins, failures) | `journalctl -u psu-autologin -f` |
| Next run | `systemctl list-timers psu-autologin.timer` |
| Log in right now | `sudo psu-autologin --force` |
| Reset backoff after fixing the password | `sudo rm -f /var/lib/psu-autologin/failures` |
| Stop it | `sudo systemctl disable --now psu-autologin.timer` |

Only `login OK` / `FAILED` / `online again` lines are logged; checks that
find the VM online stay quiet.

## Notes

- The VM's whole internet use runs under the PSU account in the env
  file, so pick it deliberately.
- If IT can whitelist the VM (by IP/MAC) so it never needs the portal,
  that's better than this script: ask before relying on it long-term.
- Portal URL can be overridden with `PSU_PORTAL_URL=...` in the env file.
