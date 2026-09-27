# infra/

Everything that creates or configures servers for this project. The
pipeline itself lives in the repo-root `Jenkinsfile` (+ `ci/scripts/`);
this folder is about the machine it runs on.

**Tooling decision:** Ansible only (`devops-toolchain.md` §5, #222). No
Terraform — Ansible drives the Azure CLI for provisioning and does the
configuration over SSH, so there's one tool and one way of running it.

## Layout

| Path | What | Status |
|---|---|---|
| [`ansible/`](ansible/README.md) | Jenkins host on Azure: `provision.yml` (VM, NSG, budget alert) + `jenkins-host.yml` (Docker, Jenkins, cloudflared) | ready, not yet applied |
| _later_ | App deploy (#221), Vault (#223), ModSecurity (#224), LGTM monitoring (#225) — new playbooks in `ansible/` | planned |

## Architecture (today)

```
 GitHub ──webhook──► Cloudflare Tunnel ──► Azure VM  mfp-jenkins  (Standard_B2s, Ubuntu 24.04)
                     (no inbound port)      ├─ Jenkins LTS  127.0.0.1:8080  (never exposed)
                                            ├─ Docker Engine  ← every pipeline stage runs as a
                                            │                   pinned container (Jenkinsfile)
                                            └─ cloudflared
 Team ──SSH (22, your IP only)──► VM        NSG allows nothing else inbound
```

## Quick start

Needs Docker + Git Bash (or any bash). Ansible doesn't run on native
Windows, so `ansible/run.sh` runs everything inside a pinned toolbox
container (Azure CLI + ansible-core).

```bash
cd infra/ansible
cp vars.example.yml vars.yml                            # budget alert email, teammates' IPs
./run.sh az login --use-device-code                     # once
./run.sh ansible-playbook provision.yml -e @vars.yml    # creates billed Azure resources
./run.sh ansible-playbook jenkins-host.yml
```

Then Jenkins UI setup: `docs/08-runbook.md` §6. Hardening checklist: #288.
Full details: [`ansible/README.md`](ansible/README.md).

## Cost & lifetime

| | |
|---|---|
| VM | `Standard_B2s`, runs **24/7**, no auto-shutdown |
| Budget | **$30/month** — email alert at 80 % / 100 %, **not** a cap |
| Until | about **2026-10-15** |
| Teardown | `./run.sh az group delete -n mfp-jenkins-rg --yes` (deletes everything in the group) |
| Pause compute billing | `./run.sh az vm deallocate -g mfp-jenkins-rg -n mfp-jenkins` (disk is kept) |

## Rules for this folder

- **No secrets in git.** `vars.yml` and the generated `inventory/azure.yml`
  are gitignored; credentials live in Jenkins' credential store, never in
  playbooks.
- **Idempotent.** Every playbook must be safe to re-run and report
  `changed=0` when nothing drifted.
- **Pinned.** Toolbox image, Azure CLI, ansible-core and apt repos are
  pinned or signed; bump deliberately.
- **Least exposure.** Open ports by exception (today: SSH from known IPs
  only).
