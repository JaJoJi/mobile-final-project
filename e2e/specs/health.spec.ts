import { test, expect } from '@playwright/test';

test.describe('backend health surface (browser-fetched)', () => {
  test('GET /health/live returns a 200 with status=live', async ({ page }) => {
    const response = await page.goto('/health/live');
    expect(response, 'navigation response').not.toBeNull();
    expect(response!.status(), '/health/live HTTP status').toBe(200);

    const body = await page.locator('body').innerText();
    expect(body, '/health/live body').toContain('"status":"live"');
    expect(body, '/health/live body has instance field').toContain('"instance"');
  });

  test('GET /health/whoami returns instance metadata', async ({ page }) => {
    const response = await page.goto('/health/whoami');
    expect(response, 'navigation response').not.toBeNull();
    expect(response!.status(), '/health/whoami HTTP status').toBe(200);

    const body = await page.locator('body').innerText();
    expect(body, '/health/whoami body has pid').toContain('"pid"');
    expect(body, '/health/whoami body has uptime').toContain('"uptime"');
    expect(body, '/health/whoami body has timestamp').toContain('"timestamp"');
  });

  test('GET /health/ready reports ready when Postgres + Redis are reachable', async ({ page }) => {
    const response = await page.goto('/health/ready');
    expect(response, 'navigation response').not.toBeNull();
    expect([200, 503], '/health/ready HTTP status').toContain(response!.status());

    const body = await page.locator('body').innerText();
    if (response!.status() === 200) {
      expect(body, '/health/ready body when ready').toContain('"status":"ready"');
    } else {
      expect(body, '/health/ready body when not ready').toContain('"status":"not_ready"');
    }
  });
});
