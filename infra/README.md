# infra/

Everything that creates or configures servers for this project. The
pipeline itself lives in the repo-root `Jenkinsfile` (+ `ci/scripts/`);
this folder is about the machine it runs on.

**Tooling decision:** Ansible only (`devops-toolchain.md` §5, #222). No
Terraform — Ansible drives the Azure CLI for provisioning and does the
configuration over SSH, so there's one tool and one way of running it.

## DevOps toolchain

| กลุ่ม | build | test | release | deploy | config | secret | operate | monitor |
|---|---|---|---|---|---|---|---|---|
| Auto Chess Mobile (116, 661, 732) | Jenkins | Gitleaks → Semgrep → Trivy → Checkov → ZAP | Docker Hub | Docker Compose | Ansible | HashiCorp Vault | nginx + ModSecurity | Beyla → Prometheus → Grafana, Tempo, Loki, Grafana Alloy + OTel SDK |

| Stage | Tool | Role in this project | Status (2026-09-28) |
|---|---|---|---|
| build | Jenkins | Multibranch on the Azure VM, polls GitHub every minute; backend + mobile build/test in pinned containers (`Jenkinsfile`) | ✅ live (#218) |
| test | Gitleaks → Semgrep → Trivy → Checkov → ZAP | secrets → SAST → dependency + image CVEs → Dockerfile/workflow misconfig → DAST on an ephemeral stack | ✅ live, blocks PRs (#219) |
| release | Docker Hub | `fiatthanapon/mobile-final-project:<sha7>` + `latest`, pushed on `main` after a `dev → main` merge — the image that passed the scans, never rebuilt | 🟡 wired, first push pending (#220) |
| deploy | Docker Compose | `docker-compose.prod.yml`: nginx → nest ×3 → Redis, Postgres primary/replica | 🟡 dev compose only (#221) |
| config | Ansible | `infra/ansible/`: Jenkins VM provisioned + configured; app deploy playbook next | 🟡 partly (#222) |
| secret | HashiCorp Vault | production mode: Raft storage, AppRole, Vault Agent renders app secrets | ⬜ (#223) |
| operate | nginx + ModSecurity | reverse proxy + OWASP CRS WAF in front of the app | 🟡 nginx only (#224) |
| monitor | Beyla, Prometheus, Grafana, Tempo, Loki, Grafana Alloy, OTel SDK | metrics (Beyla → Prometheus), traces (OTel SDK → Tempo), logs (Alloy → Loki), all in Grafana; Alloy instead of the deprecated Promtail, no mtail — log counters are LogQL queries | ⬜ (#225) |

Not in the stack (deliberately): SonarQube (SAST = Semgrep, coverage gates
live in jest/lcov), Terraform (Ansible provisions), GitHub Actions as CI
(interim only, removed in #272).

## Layout

| Path | What | Status |
|---|---|---|
| [`ansible/`](ansible/README.md) | Jenkins host on Azure: `provision.yml` (VM, NSG, budget alert) + `jenkins-host.yml` (Docker, Jenkins on loopback) | **live** — `mfp-jenkins`, malaysiawest |
| _later_ | App deploy (#221), Vault (#223), ModSecurity (#224), LGTM monitoring (#225) — new playbooks in `ansible/` | planned |

## Architecture (today)

```
 GitHub ◄──── polls every 1 min, posts ✅/❌ ──── Azure VM  mfp-jenkins  (Standard_B2als_v2, malaysiawest)
                                                 ├─ Jenkins LTS  127.0.0.1:8080 only
 Team inbox ◄── email: result + log tail ─────── │
                                                 └─ Docker Engine ← every pipeline stage runs as a
                                                                    pinned container (Jenkinsfile)
 Team ──SSH (22, allow-listed IPs) + tunnel -L 8080:127.0.0.1:8080 ──► UI
                                        NSG allows nothing else inbound
```

**Private by design** (decided 2026-09-28): no webhook, no public URL.
Jenkins polls GitHub instead, reports status on the PR and emails the
result, so the UI (SSH tunnel) is only needed for admin work.

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
| VM | `Standard_B2als_v2` (2 vCPU / 4 GB) in `malaysiawest`, runs **24/7**, no auto-shutdown |
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
