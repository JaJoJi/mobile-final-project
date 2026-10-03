# รายงาน DevOps — Auto Chess Mobile

สรุปงาน DevOps ทั้งหมดของโปรเจกต์ (CI/CD, ความปลอดภัย, โครงสร้างพื้นฐาน, การเฝ้าระวัง, ผลทดสอบ, ข้อจำกัด)
ทุกตัวเลขในเอกสารนี้มาจาก build / เครื่องจริงที่รันแล้ว ส่วนที่ **ไม่ได้ทดสอบ** ระบุไว้ชัดในหัวข้อ 14

เอกสารที่เกี่ยวข้อง: [runbook.md](runbook.md) (คำสั่งสำหรับ VM) · [docs/08-runbook.md](docs/08-runbook.md) (Jenkins) ·
[docs/14-gate-evidence.md](docs/14-gate-evidence.md) (หลักฐานแต่ละ gate) · [infra/README.md](infra/README.md)

---

## 1. ภาพรวม

```
 นักพัฒนา ── PR ──► dev ──► main
                     │        │
        GitHub webhook (HMAC)  │
                     ▼        ▼
          Jenkins (Azure VM, HTTPS)          ← CI เพียงตัวเดียว
   Gitleaks → ตรวจโค้ด/สแกน (parallel) → build image → SBOM + Trivy
   → stack ชั่วคราว (smoke, ZAP, k6 opt-in) → publish (main) → APK (main)
                                  │
                                  ▼
                 Docker Hub  fiatthanapon/mobile-final-project:<commit>
                                  │   VM มหาวิทยาลัยอยู่หลัง NAT: Jenkins เข้าไม่ถึง
                                  ▼   → VM ดึง (pull) ไป deploy เอง
         VM มหาวิทยาลัย (mob02-web02)  docker compose  `auto-chess-deploy <tag>`
   nginx+ModSecurity · nest ×3 · Postgres primary/replica · Redis · Vault
   · Beyla / Alloy / Prometheus / Loki / Tempo / Grafana · pg-backup
```

กฎ branch: งานทุกชิ้นเปิด PR เข้า `dev` เท่านั้น และมีแค่ `dev → main` ที่เป็นการ release

## 2. ชุดเครื่องมือ

| ด้าน | เครื่องมือ |
|---|---|
| CI | Jenkins (Multibranch pipeline, Docker agent ตรึง version + digest) |
| สแกนความปลอดภัย | Gitleaks, Semgrep, Trivy (fs + image), Checkov, OWASP ZAP, SBOM (CycloneDX) |
| ทดสอบ | Jest/unit + coverage, integration smoke, Flutter analyze/test, k6 (load) |
| Registry | Docker Hub (private repo) |
| IaC | Ansible (`provision.yml`, `jenkins-host.yml`, `infra/uni-vm/site.yml`) |
| Runtime | Docker Compose |
| ความลับ | HashiCorp Vault (production mode) + Vault Agent |
| WAF | nginx + ModSecurity (OWASP CRS 4.25.1) |
| Observability | Grafana Beyla, Alloy, Prometheus, Loki, Tempo, Grafana, OpenTelemetry SDK |
| HTTPS ของ Jenkins | Caddy + Let's Encrypt |

ไม่ใช้: SonarQube, GitHub Actions (ถอดแล้ว), Dependabot (ถอดใน #245)

## 3. Jenkins (CI)

- **เครื่อง:** Azure VM `mfp-jenkins` (B2als_v2, RAM 4 GB, disk 61 GB), ตั้งค่าด้วย Ansible,
  HTTPS ผ่าน Caddy ที่ `https://mfp-jenkins-psu.malaysiawest.cloudapp.azure.com`
- **Trigger:** GitHub webhook (`/github-webhook/`, ลงนาม HMAC) แทน polling; มี scan รายชั่วโมงเป็นตัวสำรอง
- **Executor 1 ตัว:** build ไม่ซ้อนกัน → cache ร่วมกันได้ที่ `/var/lib/jenkins/ci-cache`
- **จำกัดหน่วยความจำของ tool container ทุกตัว** (`MEM.small/medium/large/huge` = 512m / 1g / 1.5g / 3g)
  เพราะเคยเครื่องค้างจาก OOM เมื่อ 2026-09-28

### Stages (Jenkinsfile)

| # | Stage | ทำอะไร | รันที่ |
|---|---|---|---|
| 0 | Preflight · disk | ต้องว่างอย่างน้อย 5 GB ไม่งั้น fail | ทุก branch |
| 1 | Security · Gitleaks | สแกน secret ทั้ง git history, block เสมอ | ทุก branch |
| 2 | PR checks (parallel) | Backend lint+unit+coverage · Mobile analyze+test · Semgrep · Trivy fs · Checkov | ทุก branch |
| 3 | Backend image | docker build → SBOM (CycloneDX) → Trivy image | ทุก branch |
| 4 | Ephemeral stack | stack ชั่วคราว (3 nest + Postgres + Redis): integration smoke → Load test k6 (opt-in) → ZAP | dev / main |
| 5 | Backend · publish | push image `…:<commit>` ขึ้น Docker Hub (จาก tar เดียวกับที่สแกน) | main |
| 6 | Mobile · build APK | `flutter build apk --release` เก็บ `apk/auto-chess-<commit>.apk` | main |
| – | Report | อีเมลแจ้งผล SUCCESS/FAILURE | ทุก build |

พารามิเตอร์ปิด/เปิด gate (กด *Build with Parameters*): `ENABLE_SECURITY_SCAN`, `ENABLE_INTEGRATION_TESTS`,
`ENABLE_IMAGE_PUBLISH`, `ENABLE_APK_BUILD`, `APK_API_BASE_URL`, `ENABLE_LOAD_TEST` (ค่าเริ่มต้นปิด), `ENABLE_NOTIFICATIONS`.
build อัตโนมัติ (webhook) ใช้ค่าเริ่มต้นเสมอ — พารามิเตอร์ที่ติ๊กมีผลเฉพาะตอนกด build เอง

### ค่าความน่าเชื่อถือ

- Coverage floor: `src/game/**` ≥ 90% ต่อไฟล์, backend ส่วนอื่น ≥ 44%, mobile ≥ 84%
- ผลล่าสุดที่เก็บเป็นหลักฐาน (main #13): backend 85.3%, mobile 86.0%
- Credential อยู่ใน Jenkins เท่านั้น ไม่อยู่ใน repo; `dockerhub-token` ใช้เฉพาะ stage publish (main)
- Cache แชร์ + ล้าง workspace + cleanup รายวัน

### Hardening และสำรองข้อมูล (docs/08-runbook.md §7)

- Jenkins ฟังแค่ `127.0.0.1` (Caddy อยู่หน้า), ปิด anonymous read, ปิด sign-up, ทีมเท่านั้น
- webhook secret ลงนาม HMAC; SSH จำกัด IP แอดมินผ่าน NSG; PR จาก fork เชื่อเฉพาะผู้มีสิทธิ์ Admin/Write
- สำรอง `jenkins_home` ทุกวัน 03:15 (systemd timer) เก็บ 7 ชุด มี `master.key` + credentials ครบ
- ปักเวอร์ชัน plugin 97 ตัวใน git (`infra/jenkins/plugins.txt`)
- ตัดสินใจ **ไม่ทำ JCasC** (เสียเวลามาก ประโยชน์น้อยสำหรับเครื่องเดียว)

## 4. ความปลอดภัย (DevSecOps gates)

| Gate | ตรวจอะไร | นโยบาย |
|---|---|---|
| Gitleaks v8 | secret ใน git (ทั้ง history) | block เสมอ; allow-list เฉพาะ key ตัวอย่างที่ตั้งใจ (`.gitleaks.toml`) |
| Semgrep OSS 1.178.0 | SAST ของ backend / mobile | 0 finding |
| Trivy | CVE ใน dependency (fs) และ image | `--ignore-unfixed`, HIGH+CRITICAL; ข้อยกเว้นต้องมีเหตุผล + วันหมดอายุ |
| Checkov | Dockerfile misconfiguration | พบจริง CKV_DOCKER_7 → แก้ด้วย named base stage (#302) |
| OWASP ZAP 2.17.0 | baseline + API scan บน stack ชั่วคราว | `rules.tsv` กำหนด FAIL/IGNORE/WARN; พบจริง ZAP OOM → ปิดเฉพาะ rule 40026 |
| SBOM CycloneDX | ส่วนประกอบของ image | 434 components (main #13) |

ภาพ scanner ทุกตัวปักด้วย digest (กัน supply-chain) · รายงานทุกชนิดเก็บเป็น artifact ใน Jenkins

ผลสแกนรอบ main #13: Gitleaks 0, Semgrep 0, ZAP baseline 2 Medium / 3 Low / 3 Informational,
API scan 4 Informational, ไม่มี rule class FAIL

## 5. โครงสร้างพื้นฐานเป็นโค้ด (Ansible)

| Playbook | หน้าที่ |
|---|---|
| `infra/ansible/provision.yml` | สร้าง Azure VM, NSG (80/443), DNS label |
| `infra/ansible/jenkins-host.yml` | Docker, Jenkins, Caddy HTTPS, SSH จำกัด IP, timer ล้างดิสก์, backup timer |
| `infra/uni-vm/site.yml` | รันบน VM มหาวิทยาลัยเอง: Docker Engine, log rotation, PSU auto-login, TLS cert, Vault TLS, คำสั่ง unseal, timer สำรอง Vault |

หลักการ: รันซ้ำได้ (idempotent), secret ไม่อยู่ใน repo, `app.env` สร้างครั้งแรกเท่านั้น (`force: false`)
ปัญหาจริงที่แก้: Docker apt source ซ้ำบน VM → playbook ตรวจก่อนเพิ่ม

## 6. Release และ deploy (pull-based)

- Jenkins แค่ release artifact (image tag = commit บน main)
- **ทำไม pull:** VM อยู่หลัง NAT มหาวิทยาลัย Jenkins เข้าไม่ถึง และไม่ควรเก็บ credential ของ VM ไว้ใน Jenkins
- VM ใช้ Docker Hub token แบบ read-only; PSU captive-portal auto-login (systemd timer) ให้ VM ออกเน็ตได้
- `sudo auto-chess-deploy <tag>` (`infra/uni-vm/app/deploy.sh`): pull → `up -d` → รอ `/health/ready`
  (สูงสุด 3 นาที) → สำเร็จบันทึก tag / ล้มเหลว **rollback อัตโนมัติ** กลับ tag เดิม; log ที่ `/var/lib/auto-chess/deploy.log`
- migration รันบน nest-1 ตัวเดียว

## 7. Production stack บน VM มหาวิทยาลัย

16 container ใน compose ไฟล์เดียว (`infra/uni-vm/app/compose.yml`), image ปักด้วย digest, healthcheck + auto restart,
`mem_limit` ทุกตัว, log rotation 20 MB × 3

| กลุ่ม | บริการ |
|---|---|
| ทางเข้า | nginx + ModSecurity WAF (80 / 443 HTTPS) |
| แอป | nest-1/2/3 (stateless, `least_conn`, WebSocket) |
| ข้อมูล | PostgreSQL primary + replica (WAL streaming), Redis (state + pub/sub), `pg-backup` รายวัน |
| ความลับ | Vault + Vault Agent |
| Observability | Beyla, Alloy, Prometheus, Loki, Tempo, Grafana (:3000) |
| ตัวเลือก | pgBouncer (profile `pgbouncer`, opt-in) |

ตัวเลขจริงจาก VM (ว่าง): RAM ใช้ 1.9 / 5.9 GB, CPU < 2%, disk 9 / 48 GB (19%)
ปัญหาจริง: CPU VM ไม่มี SSE4.2 → Tempo 2.8 รันไม่ได้ ใช้ 2.7.2

## 8. Secret management (Vault)

- production mode: Raft storage + TLS listener (ไม่ใช้ dev mode); ไม่เปิดพอร์ตออกนอก
- Shamir 3 keys ต้องใช้ 2 ในการ unseal (VM ไม่มี cloud KMS); root token ถูก revoke หลังตั้งค่า
- KV v2 เก็บ Postgres / JWT / Grafana (ย้ายจาก `app.env`); AppRole ของแอปอ่านอย่างเดียว
- Vault Agent render secret ลง tmpfs → nest / Postgres / Grafana (ไม่ลงดิสก์ ไม่อยู่ใน repo)
- audit log → Loki + dashboard; snapshot รายวัน 03:30 เก็บ 7 ชุด
- หลัง reboot: `sudo auto-chess-vault-unseal` (ต้องทำมือ)
- ปัญหาจริง: `permission denied` บน `vault.db` → service `vault-perms` chown ก่อนเริ่ม (#333)

## 9. WAF (nginx + ModSecurity)

- image ทางการ `owasp/modsecurity-crs` (LTS 4.25.1, ปักด้วย digest), paranoia level 1, worker 2, mem 512m
- **โหมด DetectionOnly** (log แล้วปล่อย) — ยัง **ไม่เปิด block**
- ทดสอบ: ยิง `?id=1' OR 1=1--` → rule 942100 (SQLi), anomaly score 8 ≥ 5 (เกณฑ์ block)
- audit log JSON → Alloy → Loki; dashboard WAF แสดงตามประเภทโจมตี, top IP / URI / rule
- HTTPS: self-signed cert (`site.yml` สร้างให้); ตัวแปร `HTTPS_REDIRECT` ปิดเป็นค่าเริ่มต้น เพราะแอปบน emulator ไม่เชื่อ cert นี้
- แผน: ดู false positive จาก traffic จริงก่อนเปิดโหมด block

## 10. Observability

| สัญญาณ | ที่มา | เก็บที่ |
|---|---|---|
| Metrics (RED) | Beyla (eBPF) ไม่ต้องแก้โค้ด + node/host metrics | Prometheus (7 วัน) |
| Logs | Alloy (docker discovery) | Loki |
| Traces | OpenTelemetry SDK ใน nest (`backend/src/tracing.ts`, เปิดด้วย env) | Tempo |

- Grafana: datasource 3 ตัว provision จากไฟล์ (`infra/uni-vm/monitoring/`), **5 dashboard** provision จาก JSON ใน git:
  Overview, WAF, Infrastructure, Application, Vault audit (`allowUiUpdates: false`)
- **Trace ↔ Log correlation:** log ทุกบรรทัดมี `trace_id`/`span_id`; Grafana derived field ให้กด *View trace* ไป Tempo ได้
  (ตรวจแล้ว: Tempo รับ span 150 อัน, ดึง trace ด้วย id จาก log ได้)
- ใช้ RAM: Alloy ~224 MB, Beyla ~394 MB (วัดจริง)
- ปัญหาจริง: query ของ Tempo ค้าง → ตั้ง `frontend_worker.frontend_address: tempo:9095`; Beyla OOM → 768m; ไม่มี tag 2.5.0 → ใช้ 3.37.0

## 11. Load test (k6, `k6/load.js`)

ทดสอบ NFR: p95 round-state < 500 ms (NFR-2), ≥ 50 แมตช์ (NFR-3), p95 combat < 500 ms (NFR-14)

- 100 VU = 100 ผู้เล่น = 50 แมตช์ผ่าน WebSocket (Socket.IO) จริง; สมัคร → เข้า queue → จับคู่ด้วย matchmaking จริง → เล่น 4 รอบ
- ยิงจาก **นอก VM** ผ่านเครือข่ายจริง

| ตัวชี้วัด | ผล | เกณฑ์ |
|---|---|---|
| p95 round-state event | 112 ms | < 500 ms |
| p95 combat latency | 115 ms | < 500 ms |
| ผู้เล่นล้มเหลว | 0 / 100 | 0 |
| 5xx | 0 | – |
| VM ช่วงยิง | CPU ~10%, RAM ~38%, disk 19% | – |
| Jenkins (stack ชั่วคราว, 20 ผู้เล่น) | p95 31 / 51 ms | ผ่าน |

สิ่งที่เจอ: คอขวดแรกคือ **matchmaking จับคู่ได้ 1 แมตช์/วินาที** (BullMQ poll 1000 ms, จับคู่ 1 แมตช์ต่อ tick) ไม่ใช่ CPU;
สมัครพร้อมกัน 100 คน p95 ~4.5 s (bcrypt) แต่เมื่อทยอยเข้าเหลือ ~0.2 s;
รอบแรกล้ม 58% เพราะสคริปต์ไม่สมจริง (ผู้เล่น 100 คนเข้าใน 3 วินาที) → ปรับให้ทยอยเข้าและมีเวลาคิด แล้ววัดใหม่ได้ 0 error

## 12. Mobile (APK จาก Jenkins)

- stage `Mobile · build APK` ทำงานหลัง publish (เฉพาะ main): `flutter build apk --release`
  เวอร์ชัน `0.1.<build number>` เก็บ `apk/auto-chess-<commit>.apk` เป็น artifact (fingerprint)
- ที่อยู่ backend ใส่ตอน build จากพารามิเตอร์ `APK_API_BASE_URL` (ค่าเริ่มต้น VM มหาวิทยาลัย; `WS_BASE_URL` คำนวณให้)
- ไฟล์ `mobile/android/` สร้างด้วย `flutter create` แล้ว commit; เปิด INTERNET + cleartext http (backend ยังเป็น http)
- ปัญหาจริง: Gradle ถูก kill (heap 8 GB ใน container 1.5 GB) → ปรับ heap/memory + `MEM.huge`
- สถานะ: build ผ่านและได้ไฟล์ APK; **การทดสอบใน emulator เป็นงานของเพื่อน (ต้องอยู่เครือข่าย PSU)**

## 13. เหตุการณ์ที่เจอและวิธีแก้

| ปัญหา | แก้ |
|---|---|
| ดิสก์ Jenkins เต็ม (cache ในทุก workspace) | cache ร่วม + ล้าง workspace + timer รายวัน + stage Preflight |
| เครื่อง Jenkins ค้างจาก OOM | จำกัดหน่วยความจำ container ทุกตัว |
| Checkov CKV_DOCKER_7 | named base stage |
| ZAP OOM | ปิดเฉพาะ rule 40026 |
| Gitleaks `leaks found: 1` (key ตัวอย่างใน history) | allow-list แบบ regex (#373) |
| Vault `permission denied` | `vault-perms` chown (#333) |
| Beyla ไม่มี tag / OOM | tag 3.37.0, mem 768m |
| Tempo ต้องการ CPU SSE4.2 | ใช้ 2.7.2 |
| Tempo query ค้าง | worker ชี้ `tempo:9095` |
| Dashboard CPU ไม่มีข้อมูล / p95 ถูก `/auth/register` ครอบ | แก้ query (`scalar()`), แยกกราฟ |
| พารามิเตอร์ `ENABLE_LOAD_TEST` หาย / stage k6 ถูกข้าม | เพิ่มพารามิเตอร์ + ปรับ `when` (#370, #372) |
| SSH เข้า Jenkins ไม่ได้ (IP แอดมินเปลี่ยน, NSG) | อัปเดต `AllowSSHFromAdmins` |
| Gradle ถูก kill | heap/memory ใน `gradle.properties` |
| อีเมลแจ้งผลส่งไม่ได้ (`Failed to create e-mail address`) | ตัวอักษรซ่อนใน credential `notify-email` → พิมพ์ใหม่ (**ยังไม่ยืนยันว่าแก้แล้ว**) |

## 14. ข้อจำกัดและสิ่งที่ยังไม่ได้ทดสอบ

**ข้อจำกัดของระบบ**
- HTTPS ของแอปเป็น self-signed (VM หลัง NAT ไม่มีชื่อโดเมนสาธารณะ)
- WAF ยัง DetectionOnly
- Vault ต้อง unseal ด้วยมือหลัง reboot (ไม่มี cloud KMS)
- matchmaking จับคู่ได้ 1 แมตช์/วินาที
- pgBouncer เป็น opt-in และยังไม่ได้ทดสอบ

**ยังไม่ได้ทดสอบ / ไม่ได้ทำ**
- reboot test และ restore แบบเต็ม (Vault, Postgres, Jenkins) — **ไม่ได้ทดสอบ** (ไม่ใช่ "ผ่าน")
- red proof ของ gate: ไม่ได้จงใจทำให้ gate แดงบน branch ทิ้ง (ตัดสินใจเมื่อ 2026-10-03);
  gate ที่เคยแดงจริงบน build จริง: Checkov, coverage floor, Preflight disk, ZAP.
  Gitleaks / Semgrep / Trivy fs / unit / type check / Flutter analyze เคยเห็นแค่เขียว
- เพดานสูงสุดของระบบ: ทดสอบแค่ 50 แมตช์ (CPU ~10%) จึงยังไม่รู้เพดาน; NFR-3 แสดงว่า 50 แมตช์เสร็จในราว 1 นาที ยังไม่ได้นับจำนวนที่เล่นพร้อมกันจริง
- การทดสอบ APK ใน emulator (เพื่อน)
- branch protection (PR-only) — รอเจ้าของ repo (#280)
- bug เล็กใน backend ที่ยังไม่แก้: `applyDamageAndAdvance` โยน `internal` เมื่อแพ้ race กับ `handleDisconnect`
- ยังไม่ release `dev → main` ครั้งล่าสุด (เพื่อนทำ)

## 15. งานที่เก็บไว้ (nice-to-have, issue #289)

เก็บไว้ทั้งหมดโดยตั้งใจ: แจ้งเตือน dependency แบบไม่สร้าง PR (Dependabot alerts / Renovate dashboard),
rescan Trivy รายคืน, `/health` คืน git sha + เปลี่ยนชื่อ stage เป็น `Release - Production` (หลัง UI เสร็จ),
Jenkins health ใน Grafana, pre-commit (gitleaks + eslint) — ไว้โปรเจกต์หน้า.
ตัดทิ้ง: ปักเวอร์ชัน GitHub Actions ด้วย SHA (ไม่ใช้ GH Actions แล้ว), Semgrep diff-aware (ตอนนี้ 0 finding)

## 16. แผนที่ไฟล์

| เรื่อง | ไฟล์ |
|---|---|
| pipeline | `Jenkinsfile`, `ci/` |
| Jenkins plugin / export | `infra/jenkins/plugins.txt`, `infra/jenkins/export-plugins.sh` |
| Azure + Jenkins host | `infra/ansible/` |
| VM มหาวิทยาลัย | `infra/uni-vm/site.yml`, `infra/uni-vm/app/` (compose, deploy.sh) |
| Vault | `infra/uni-vm/vault/` |
| Monitoring | `infra/uni-vm/monitoring/` (alloy, prometheus, loki, tempo, grafana) |
| WAF | `nginx/modsec/` |
| Tracing | `backend/src/tracing.ts` |
| Load test | `k6/load.js` |
| Android | `mobile/android/` |
| คำสั่งสำหรับ VM | `runbook.md` |
| Runbook Jenkins + hardening | `docs/08-runbook.md` |
| หลักฐาน gate | `docs/14-gate-evidence.md` |
