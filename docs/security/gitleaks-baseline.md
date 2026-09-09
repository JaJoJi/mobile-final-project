# gitleaks baseline scan — P3-DO-07 (#191)

The `gitleaks.yml` workflow scans **PR diffs** on every pull request. This
note records the **one-time full-history** scan of the whole repo.

## How to (re)run the full-history scan

```bash
docker run --rm -v "$PWD:/repo" -w /repo zricethezav/gitleaks:latest \
  detect --source /repo --config /repo/.gitleaks.toml --redact -v
```

or, in CI, the first run of `gitleaks.yml` on a `push` to `dev` scans the
history reachable from that commit.

## Result

> **Status: pending first run.** This branch (`P3-DO-07`) adds the config
> and workflow; the full-history scan is executed by the first
> `gitleaks.yml` run after merge (push to `dev`). Paste the summary here
> and flip the status once that run is green.

Expected clean given `.gitleaks.toml` already allowlists the known
placeholders:

| Location | Value | Why it is not a secret |
|---|---|---|
| `.env.example` | `JWT_SECRET=dev_jwt_secret_change_me_…` | Documented dev default; real value from a secret manager in prod (P3-DO-04 / #139). |
| `.env.example` | `POSTGRES_PASSWORD=postgres` | Local dev DB credential. |
| `.env.example` | `PGADMIN_PASSWORD=admin` | Local pgAdmin dev credential. |
| `docker-compose.yml` | `replicator_secret` | Local replication password for the compose stack. |
| `.github/workflows/backend-ci.yml` | `ci_jwt_secret_not_a_real_secret_…` | Ephemeral CI-only literal; the CI Postgres/Redis are throwaway service containers. |

## Accepted findings

None yet. Any future accepted finding goes in `.gitleaks.toml` under
`[allowlist]` with a one-line reason, and is summarised here.
