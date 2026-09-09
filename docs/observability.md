# Observability — P3-DO-03 (#138)

> **Status: SCAFFOLDING ONLY. Issue #138 is NOT done.**
> The compose stack + config below come up and run, but the backend does
> not emit application metrics or structured logs yet. Do not tick the
> issue's "Done when" boxes on the strength of this branch.

## What is wired up (this branch)

| Component | State | Notes |
|---|---|---|
| `prometheus` (`:9090`) | runs | scrapes itself; `nestjs` targets (nest-1/2/3) show **DOWN** — no `/metrics` yet |
| `prometheus/rules/*.yml` | loaded | `CombatP95TooHigh` (NFR-14), `MatchDurationP99Degraded` — never fire until the histograms exist |
| `loki` (`:3100`) | runs | single-binary, filesystem store, 7-day retention |
| `promtail` | runs | ships every `auto_chess` container's stdout to Loki, labelled by service |
| `grafana` (`:3001`, admin/admin) | runs | Prometheus + Loki datasources provisioned; `Auto Chess — Overview` dashboard loaded as a **stub** (panels = "No data") |

## Bring it up

```bash
cp .env.example .env   # sets GRAFANA_ADMIN_*
docker compose up -d prometheus loki promtail grafana
# Grafana:     http://localhost:3001  (admin / admin)
# Prometheus:  http://localhost:9090/targets
```

Container logs already flow to Loki now — in Grafana → Explore → Loki:
`{project="auto_chess", service=~"nest-.*"}`.

## What is left (backend half of #138 — not in scope for this branch)

- [ ] `@willsoto/nestjs-prometheus` + `prom-client` in `backend`, `/metrics` endpoint
- [ ] Custom metrics: `match_duration_seconds`, `combat_duration_seconds`,
      `ws_messages_total`, `shop_actions_total`, `phase_flip_total`
      (bounded label sets only — no `userId`)
- [ ] Instrument `match.service.ts`, `runtime/combat.coordinator.ts`, `ws/ws.gateway.ts`
- [ ] pino JSON logging; add a `json:` `pipeline_stages` block to `promtail/promtail.yml`
      to promote `level` / `matchId` to labels
- [ ] Replace `grafana/dashboards/auto_chess.json` with a real export once panels have data
- [ ] Wire an Alertmanager (or Grafana alerting) receiver for `CombatP95TooHigh`
- [ ] Update `docs/03-architecture.md` with the observability topology

## Files

```
prometheus/prometheus.yml
prometheus/rules/combat-latency.yml
loki/loki-config.yml
promtail/promtail.yml
grafana/provisioning/datasources/datasources.yml
grafana/provisioning/dashboards/dashboards.yml
grafana/dashboards/auto_chess.json          # stub
docker-compose.yml                           # prometheus, loki, promtail, grafana services
```
