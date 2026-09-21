# Auto Chess — Playwright E2E

Browser-driven end-to-end tests for the Auto Chess backend (Lab 05, Jenkins CI/CD).

The project has no React/Vue/Angular web frontend — Flutter is the only
client. The smallest realistic browser-testable flow the running backend
exposes is the **NestJS Swagger UI** at `/api/docs`, plus the real REST
endpoints. That is what these tests cover.

## Specs

| Spec file | What it proves |
|---|---|
| `specs/health.spec.ts` | `GET /health/live`, `/health/whoami`, `/health/ready` are reachable in a real browser and report the expected fields. |
| `specs/swagger-ui.spec.ts` | `/api/docs` renders the Swagger UI with the Auto Chess API title, and `/api/docs-json` returns a valid OpenAPI 3 document that describes `/auth/register`, `/auth/login`, `/user/me`. |
| `specs/auth-flow.spec.ts` | Register → login → `/user/me` round-trip works against the real backend and real Postgres; duplicate registration returns 409; `/user/me` without a Bearer token returns 401; Swagger UI's "Try it out" for `/auth/register` returns 201. |

## Reports

- JUnit XML: `e2e/reports/junit-e2e.xml` — for the Jenkins `junit` step
- HTML: `e2e/playwright-report/index.html` — for `archiveArtifacts`

## Local run (host, no Docker)

Requires a backend reachable at `BASE_URL` (default `http://localhost:3000`).

```bash
cd e2e
npm install
npx playwright install --with-deps chromium
BASE_URL=http://localhost:3000 npm test
```

## Local run in Docker (full stack)

Reuses the existing `docker-compose.yml` (Postgres + Redis + `nest-1`)
plus the override `docker-compose.e2e.yml` (adds the `playwright`
service + a `nest-1` healthcheck).

```bash
docker compose -f docker-compose.yml -f docker-compose.e2e.yml \
  up --abort-on-container-exit --exit-code-from playwright
```

When the run finishes, the JUnit XML and HTML report are inside the
`playwright` container at `/e2e/reports/junit-e2e.xml` and
`/e2e/playwright-report/`. To copy them out:

```bash
docker compose -f docker-compose.yml -f docker-compose.e2e.yml \
  cp playwright:/e2e/reports ./e2e-reports
```

## Jenkins integration (not wired yet)

The Jenkinsfile is intentionally untouched in this change. When we wire
it in, the Jenkins agent is on the `jenkins` Docker network; we'll either
attach the `playwright` service to that network via the override, or run
`docker compose ... up` from inside the agent. Same commands, different
network glue.
