import { IncomingMessage, ServerResponse } from 'http';

/**
 * P3-DO-21 — trace/log correlation, cheap version: no OTel SDK inside
 * this process. The plan was that Beyla (Direct mode) propagates a W3C
 * `traceparent` header across the nginx->nest-1/2/3 hop, so this file
 * would just read it and stamp `req.traceId` for `LoggerModule`'s
 * `customProps` to put on every pino line.
 *
 * VERIFIED NOT WORKING (Beyla v3.36.0, tested for real, not assumed):
 * a request through the actual nginx->backend topology, both sides
 * eBPF-instrumented, `BEYLA_BPF_CONTEXT_PROPAGATION=all` set on both —
 * the app never sees a `traceparent` header. Tried three configs
 * (single-hop without propagation, single-hop with propagation, full
 * two-hop topology with propagation on both sides); all three came back
 * with no header in `req.headers`. Beyla's docs describe propagation as
 * injecting into *outgoing* requests from an instrumented process, and
 * that evidently isn't reaching this app's inbound side the way the
 * design assumed.
 *
 * Left in place because it's harmless (an always-undefined `req.traceId`
 * changes nothing) and costs nothing to keep — but trace_id will not
 * appear in logs from this path today. If correlation is still wanted,
 * the working alternative is a real OTel SDK in the app (auto-instrument
 * NestJS, generate/propagate context itself) — the heavier approach this
 * design deliberately tried to avoid. That's a real decision for
 * whoever picks this back up, not something resolved by more config here.
 *
 * `traceparent` shape (W3C Trace Context), for whenever this does see
 * one: `version-traceid-parentid-flags`, e.g.
 * `00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01` — the trace
 * id is the second field, a 32-char lowercase hex string.
 */
const TRACEPARENT_RE = /^[0-9a-f]{2}-([0-9a-f]{32})-[0-9a-f]{16}-[0-9a-f]{2}$/i;

export function extractTraceId(
  headers: IncomingMessage['headers'],
): string | undefined {
  const raw = headers['traceparent'];
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (!value) return undefined;
  const match = TRACEPARENT_RE.exec(value);
  return match?.[1];
}

export function traceContextMiddleware(
  req: IncomingMessage & { traceId?: string },
  _res: ServerResponse,
  next: () => void,
): void {
  req.traceId = extractTraceId(req.headers);
  next();
}
