import { test, expect } from '@playwright/test';

function uniqueCreds(): { email: string; username: string; password: string } {
  const nonce = `${Date.now()}${Math.floor(Math.random() * 1e6)}`;
  return {
    email: `e2e-${nonce}@example.com`,
    username: `e2e_${nonce}`.slice(0, 20),
    password: 'pass1234',
  };
}

test.describe('auth REST flow (real backend, real Postgres)', () => {
  test('register → login → /user/me round-trip', async ({ request, page }) => {
    const creds = uniqueCreds();

    const registerRes = await request.post('/auth/register', { data: creds });
    expect(registerRes.status(), 'POST /auth/register HTTP status').toBe(201);
    const registered = (await registerRes.json()) as {
      userId: string;
      accessToken: string;
      refreshToken: string;
    };
    expect(typeof registered.userId, 'register.userId is a string').toBe('string');
    expect(registered.userId, 'register.userId is a UUID').toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    );
    expect(typeof registered.accessToken, 'register.accessToken is a string').toBe('string');
    expect(registered.accessToken.length, 'register.accessToken non-empty').toBeGreaterThan(0);
    expect(typeof registered.refreshToken, 'register.refreshToken is a string').toBe('string');
    expect(registered.refreshToken.length, 'register.refreshToken non-empty').toBeGreaterThan(0);

    const loginRes = await request.post('/auth/login', {
      data: { email: creds.email, password: creds.password },
    });
    expect(loginRes.status(), 'POST /auth/login HTTP status').toBe(200);
    const loggedIn = (await loginRes.json()) as {
      userId: string;
      accessToken: string;
      refreshToken: string;
    };
    expect(loggedIn.userId, 'login.userId matches register.userId').toBe(registered.userId);
    expect(loggedIn.accessToken, 'login.accessToken non-empty').toBeTruthy();

    const meRes = await request.get('/user/me', {
      headers: { Authorization: `Bearer ${loggedIn.accessToken}` },
    });
    expect(meRes.status(), 'GET /user/me HTTP status').toBe(200);
    const me = (await meRes.json()) as {
      id: string;
      email: string;
      username: string;
      rating: unknown;
    };
    expect(me.id, '/user/me id matches userId').toBe(registered.userId);
    expect(me.email, '/user/me email matches').toBe(creds.email);
    expect(me.username, '/user/me username matches').toBe(creds.username);
    expect(me.rating, '/user/me rating is defined').toBeDefined();
    expect(typeof me.rating, '/user/me rating is a number').toBe('number');

    const noAuthRes = await request.get('/user/me');
    expect(noAuthRes.status(), 'GET /user/me without token is 401').toBe(401);
  });

  test('registering the same email twice returns 409', async ({ request }) => {
    const creds = uniqueCreds();
    const first = await request.post('/auth/register', { data: creds });
    expect(first.status(), 'first register HTTP status').toBe(201);
    const second = await request.post('/auth/register', { data: creds });
    expect(second.status(), 'duplicate register HTTP status').toBe(409);
  });

  test('Swagger UI: /auth/register operation block is interactive in the browser', async ({ page }) => {
    await page.goto('/api/docs');
    await expect(page.locator('section.swagger-ui div.swagger-ui')).toBeVisible();

    const registerOp = page.locator(
      '.opblock:has([data-path="/auth/register"])',
    );
    await expect(registerOp, '/auth/register operation block').toBeVisible();

    await registerOp.locator('.opblock-summary').click();

    const tryOutBtn = registerOp.locator('.try-out__btn');
    await expect(tryOutBtn, 'Try it out button after expand').toBeVisible();
    await tryOutBtn.click();

    const executeBtn = registerOp.locator('.execute');
    await expect(executeBtn, 'Execute button after Try it out').toBeVisible();
  });
});
