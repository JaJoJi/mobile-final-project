import { request } from '@playwright/test';

const BASE_URL = process.env.BASE_URL ?? 'http://localhost:3000';
const TIMEOUT_MS = 90_000;
const POLL_INTERVAL_MS = 1000;

export default async function globalSetup(): Promise<void> {
  const deadline = Date.now() + TIMEOUT_MS;
  const ctx = await request.newContext({ baseURL: BASE_URL });

  console.log(`[global-setup] waiting for ${BASE_URL}/health/live (timeout ${TIMEOUT_MS} ms)`);

  let lastError: unknown = null;
  while (Date.now() < deadline) {
    try {
      const res = await ctx.get('/health/live');
      if (res.ok()) {
        await ctx.dispose();
        console.log(`[global-setup] backend is live`);
        return;
      }
    } catch (err) {
      lastError = err;
    }
    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
  }

  await ctx.dispose();
  throw new Error(
    `[global-setup] backend at ${BASE_URL} did not respond 200 within ${TIMEOUT_MS} ms` +
      (lastError ? ` (last error: ${String(lastError)})` : ''),
  );
}
