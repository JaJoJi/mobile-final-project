# CI gate evidence (#287)

DevOps Master Guide rule #1: *a gate that has never been seen red is not
done.* This page records, per gate, a **green** build and a **red** build.
Green evidence below comes from a real Jenkins run; red evidence is still
to be collected (see "Red proofs").

## Green: every gate passes (Jenkins `mobile-final-project/main` #13)

All 15 stages green, including the image publish
(`Preflight · disk` → `Security · Gitleaks` → PR checks ×5 → `Backend · docker build`
→ `Security · SBOM + Trivy image` → `Stack · up` → `Backend · integration smoke`
→ `Security · ZAP` → `Backend · publish to Docker Hub`). Archived artifacts of
that build (kept outside the repo, 4 MB):

| Gate | Result in build #13 | Evidence file |
|---|---|---|
| Gitleaks (v8) | **0 findings** | `gitleaks.sarif` |
| Semgrep OSS 1.178.0 | **0 findings** | `semgrep.sarif` |
| Backend unit tests + coverage | statements **1653 / 1938 = 85.3 %** (floors: `src/game/**` ≥ 90 % per file, rest ≥ 44 %) | `backend/coverage/` |
| Mobile analyze + test + coverage | lines **5438 / 6321 = 86.0 %** (floor 84 %) | `mobile/coverage/lcov.info` |
| SBOM (CycloneDX 1.7) | **434 components** of `backend-image.tar` | `sbom.cdx.json` |
| Trivy fs / Trivy image (`--ignore-unfixed`, HIGH+CRITICAL) | exit 0 (stages green) | Jenkins stage log |
| Checkov (Dockerfile) | stage green | Jenkins stage log |
| Ephemeral stack + integration smoke | 3 Nest instances + Postgres + Redis, smoke scripts pass | `stack-logs/nest-{1,2,3}.log` |
| OWASP ZAP 2.17.0 | baseline: 2 Medium / 3 Low / 3 Informational, API scan: 4 Informational; **no FAIL-class rule** (injection classes are FAIL in `rules.tsv`) | `zap-reports/` |
| Publish | image pushed to Docker Hub from the exact scanned tar | Jenkins stage log |

## Red proofs: not collected

Deliberately breaking each gate on throwaway branches was dropped (decision
2026-10-03). Gates that were seen failing on real builds during the project:
**Checkov** (CKV_DOCKER_7 on `backend/Dockerfile`, fixed with a named base
stage, #302), **backend coverage floor**, **Preflight · disk** (disk full),
and **ZAP** (scanner error rc=3, fixed by ignoring rule 40026). The other
gates (Gitleaks, Semgrep, Trivy fs, unit test, type check, Flutter
analyze/format) have only been seen green here.
