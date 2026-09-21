import { test, expect } from '@playwright/test';

test.describe('Swagger UI and OpenAPI document (real backend)', () => {
  test('GET /api/docs renders the Swagger UI page with the Auto Chess API title', async ({ page }) => {
    const response = await page.goto('/api/docs');
    expect(response, 'navigation response').not.toBeNull();
    expect(response!.status(), '/api/docs HTTP status').toBe(200);

    await expect(page.locator('section.swagger-ui div.swagger-ui')).toBeVisible();

    const titleText = await page.title();
    expect(titleText.toLowerCase(), '<title> contains Swagger UI').toContain('swagger');

    const info = page.locator('.info, .title');
    await expect(info.first()).toBeVisible();
    await expect(info.first()).toContainText('Auto Chess API');

    const responseJsonLink = page.locator('[data-path="/api/docs-json"]');
    await expect(responseJsonLink, 'raw spec link in UI').toHaveCount(0);

    const registerOp = page.locator('[data-path="/auth/register"]');
    await expect(registerOp, '/auth/register operation block in Swagger UI').toBeVisible();

    const loginOp = page.locator('[data-path="/auth/login"]');
    await expect(loginOp, '/auth/login operation block in Swagger UI').toBeVisible();

    const meOp = page.locator('[data-path="/user/me"]').first();
    await expect(meOp, '/user/me operation block in Swagger UI').toBeVisible();
  });

  test('GET /api/docs-json is a valid OpenAPI document describing the API', async ({ request }) => {
    const response = await request.get('/api/docs-json');
    expect(response.status(), '/api/docs-json HTTP status').toBe(200);
    expect(response.headers()['content-type'], 'Content-Type').toContain('application/json');

    const doc = (await response.json()) as {
      openapi?: string;
      info?: { title?: string; version?: string };
      paths?: Record<string, Record<string, unknown>>;
    };

    expect(typeof doc.openapi, 'OpenAPI version string').toBe('string');
    expect(doc.openapi, 'OpenAPI version starts with 3.').toMatch(/^3\./);

    expect(doc.info, 'info block').toBeDefined();
    expect(doc.info!.title, 'info.title').toBe('Auto Chess API');
    expect(typeof doc.info!.version, 'info.version is a string').toBe('string');

    expect(doc.paths, 'paths object').toBeDefined();
    expect(doc.paths!['/auth/register'], '/auth/register path exists').toBeDefined();
    expect(doc.paths!['/auth/register'].post, '/auth/register has POST').toBeDefined();

    expect(doc.paths!['/auth/login'], '/auth/login path exists').toBeDefined();
    expect(doc.paths!['/auth/login'].post, '/auth/login has POST').toBeDefined();

    expect(doc.paths!['/user/me'], '/user/me path exists').toBeDefined();
    expect(doc.paths!['/user/me'].get, '/user/me has GET').toBeDefined();
  });
});
