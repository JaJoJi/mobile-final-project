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

## Red proofs (to collect)

One throwaway branch per gate, **never merged**, from `dev` plus one small
file that breaks exactly that gate; open a *draft* PR into `dev` so the PR
build runs every gate, copy the build number, then close the PR and delete
the branch. Each file below is an invented example, not a real credential.

| Gate | How to break it (one new file) | Expected red stage | Red build | Green build |
|---|---|---|---|---|
| Type check / lint | `backend/src/x.ts`: `export const a: number = 'text';` | Backend · lint + unit test | _todo_ | #13 (main) |
| Unit test | `backend/src/x.spec.ts`: `expect(1 + 1).toBe(3)` | Backend · lint + unit test | _todo_ | #13 |
| Coverage floor (game ≥ 90 %) | `backend/src/game/x.ts`: a 60-branch function nobody tests | Backend · lint + unit test (`coverageThreshold`) | _todo_ | #13 |
| Flutter analyze | `mobile/lib/x.dart`: `const int a = 'text';` | Mobile · analyze + test | _todo_ | #13 |
| Dart format | `mobile/lib/y.dart`: `const   int   a=1 ;` | Mobile · analyze + test | _todo_ | #13 |
| Gitleaks | `x.txt`: `api_key = "<32+ random-looking chars>"` (matches `generic-api-key`); **only on the throwaway branch, never on `dev`** (Gitleaks scans history) | Security · Gitleaks | _todo_ | #13 |
| Semgrep | `backend/src/x.ts`: `eval(req.query.x)` | Security · Semgrep | _todo_ | #13 |
| Trivy fs | `requirements.txt`: `django==2.2.0` (fixed HIGH/CRITICAL CVEs) | Security · Trivy fs | _todo_ | #13 |
| Checkov | `ci/x/Dockerfile`: `FROM node:latest` / `ADD . /app` / no `USER` / no `HEALTHCHECK` | Security · Checkov | _todo_ | #13 |
| Trivy image / ZAP / integration smoke | covered by their own issues | | | #13 |
| Branch guard (`feature → main` blocked) | needs the rulesets of #280 | | blocked by #280 | |

The branch-per-gate script (`gate-proof.sh`: `create <gate|all>`, `status`,
`cleanup`) was written but **not run**: pushing deliberately vulnerable files
to the public repo needs a person to decide. Run it yourself from outside
the repo if you want it automated, or create the branches by hand from the
table.

When a row is done: fill in the two build numbers, link the Jenkins stage
view (screenshot) in the PR that updates this page, and tick the matching box
in #287.
