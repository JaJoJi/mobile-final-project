# Jenkins host on Azure — Ansible

Ansible is the project's infra tool (`devops-toolchain.md` §5, #222) — no
Terraform. Two playbooks:

| Playbook | Runs against | Does |
|---|---|---|
| `provision.yml` | localhost → Azure CLI | resource group, VM (Ubuntu 24.04, `Standard_B2s`, 64 GB), NSG with **SSH only, from your IP + `admin_cidrs`**, Cost Management budget alert |
| `jenkins-host.yml` | the VM over SSH | Docker Engine, Jenkins LTS, cloudflared; verifies the `jenkins` user can run docker and Jenkins answers on `:8080` |

Both are idempotent: re-running changes nothing unless something drifted
(verified: second run of `jenkins-host.yml` → `changed=0`).

Ansible's controller doesn't run on native Windows, so everything runs
through a pinned toolbox container (`Dockerfile`: Azure CLI 2.90.0 +
ansible-core 2.21.4) via `run.sh`. Needs only Docker + Git Bash.

## Cost

`Standard_B2s` ≈ **$30/month running 24/7** (decided 2026-09-28: no
auto-shutdown so teammates can build any time; project runs to about
**2026-10-15**). The budget created by `provision.yml` only **emails**
at 80 % / 100 % — it never stops the VM. When the project is over:

```bash
./run.sh az group delete -n mfp-jenkins-rg --yes   # deletes EVERYTHING in it
```

To pause billing for compute but keep the disk: `./run.sh az vm deallocate -g mfp-jenkins-rg -n mfp-jenkins`.

## Steps

```bash
cd infra/ansible
cp vars.example.yml vars.yml                   # set budget_alert_emails (+ teammates' IPs)

./run.sh az login --use-device-code            # once; stored in docker volume mfp-azure-cli
./run.sh az account show -o table              # confirm "Azure for Students"

./run.sh ansible-playbook provision.yml -e @vars.yml   # creates billed resources
./run.sh ansible-playbook jenkins-host.yml
```

`provision.yml` writes `inventory/azure.yml` (gitignored) with the VM's IP
for `jenkins-host.yml`. `SSH_KEY=~/.ssh/other_key ./run.sh ...` to use a
different key pair (default `~/.ssh/id_ed25519`).

## After the playbooks

1. **Open Jenkins** through an SSH tunnel (Jenkins is not exposed by the NSG):
   ```bash
   ssh -L 8080:127.0.0.1:8080 azureuser@<vm-ip>     # then http://localhost:8080
   ssh azureuser@<vm-ip> sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```
2. Finish setup per `docs/08-runbook.md` §6 (plugins, Multibranch job,
   credentials) and the hardening checklist in #288.
3. **GitHub webhook** needs a public HTTPS URL — use a Cloudflare Tunnel
   (cloudflared is installed), not an open port:
   - **Named tunnel** (stable URL, needs a domain on Cloudflare):
     `cloudflared tunnel login` → `cloudflared tunnel create jenkins-mfp` →
     `cloudflared tunnel route dns jenkins-mfp jenkins.<domain>` →
     `sudo cloudflared service install <token>`
   - **Quick tunnel** (no domain, URL changes on every restart):
     `cloudflared tunnel --url http://localhost:8080`, then point the
     webhook at `https://<printed-url>/github-webhook/`.

## Teammate IP changed?

Add it to `admin_cidrs` in `vars.yml` and re-run `provision.yml` — only
the NSG rule is updated.
