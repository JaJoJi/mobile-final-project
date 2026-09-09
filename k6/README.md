# k6 load test — P3-DO-05 (#140)

Proves the load NFRs against the full `docker compose` stack.

| NFR | What | k6 metric | Threshold |
|---|---|---|---|
| NFR-2 | p95 round-state WS event | `round_state_latency_ms` | `p(95)<500` |
| NFR-14 | p95 combat latency | `combat_latency_ms` | `p(95)<500` |
| NFR-3 | ≥ 50 concurrent matches | 50 VUs (`--env VUS=`) | — |
| — | request error rate | `http_req_failed` | `rate<0.01` |
| — | matchmaking success | `match_found_rate` | `rate>0.90` |

## Run locally

```bash
docker compose up -d --build
# wait for the stack to be healthy
curl -sf http://localhost/health/ready

# with a local k6 binary
k6 run --env BASE_URL=http://localhost --env WS_URL=ws://localhost k6/load.js

# or via Docker (no k6 install)
docker run --rm -i --network host \
  -e BASE_URL=http://localhost -e WS_URL=ws://localhost \
  grafana/k6 run - < k6/load.js
```

Knobs (all `--env` / `-e`): `VUS` (default 50), `DURATION` (`5m`),
`MATCH_HOLD_S` (90), `BASE_URL`, `WS_URL`.

## CI

`.github/workflows/load-test.yml` runs this weekly (cron) and on manual
`workflow_dispatch`. It brings the stack up, runs k6 in a container,
uploads `k6-summary.json` + `k6-report.html` as artifacts, then deletes
the `k6_*@load.local` users it created.

The job is **not** wired into PR CI — a 5-minute 50-VU test is too slow
and too noisy for every push.

## ⚠️ Known gap — latency thresholds are not live yet

Latency is `client_now - event.sentAt`. The backend does **not** emit
`sentAt` on WS events yet (small change in `backend/src/ws/ws.gateway.ts`
/ the pubsub publish path — listed in the issue's "Files to touch").

Until that lands:

- `round_state_latency_ms` / `combat_latency_ms` collect **zero samples**
- k6 reports a no-sample threshold as passing, so NFR-2 / NFR-14 are
  **not enforced** yet — the script still exercises the system and
  enforces the connection/error/matchmaking thresholds

Once the backend emits `sentAt`, no script change is needed (the parser
already tolerates `sentAt` / `emittedAt` / `meta.sentAt`); just confirm
the trends fill and the p95 thresholds hold.

## Notes

- **VUs are not users.** Each VU logs in, opens a socket.io v4 websocket,
  joins matchmaking, stays connected `MATCH_HOLD_S` receiving phase +
  combat events, then leaves. No shop actions — out of scope for an MVP
  load test.
- **Baseline on real hardware.** GitHub-hosted runners are noisy; treat
  CI numbers as regression signal, not absolute capacity. Run against the
  staging VM (#193) for a real baseline.
