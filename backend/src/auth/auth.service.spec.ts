import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';

const makeService = (users: Partial<{
  create: (input: any) => Promise<any>;
  findByEmail: (email: string) => Promise<any>;
  findById: (id: string) => Promise<any>;
}>) => new AuthService(
  users as any,
  new JwtService({ secret: 'test-secret-32-bytes-long-enough!!' }),
);

const stored = (overrides: Record<string, unknown> = {}) => ({
  id: 'user-1',
  email: 'alice@example.com',
  username: 'alice',
  passwordHash: bcrypt.hashSync('correct-horse', 10),
  ...overrides,
});

describe('AuthService.register (#308)', () => {
  it('hashes with bcrypt(10) and returns all three tokens', async () => {
    const created: any[] = [];
    const service = makeService({
      create: async (input: any) => {
        created.push(input);
        return { id: 'user-1', email: input.email };
      },
    });
    const res = await service.register({
      email: 'Alice@Example.com',
      username: 'alice',
      password: 'correct-horse',
    } as any);
    expect(res.userId).toBe('user-1');
    expect(res.accessToken).toEqual(expect.any(String));
    expect(res.refreshToken).toEqual(expect.any(String));
    expect(res.accessToken).not.toBe(res.refreshToken);
    expect(created[0].passwordHash).not.toContain('correct-horse');
    expect(created[0].passwordHash).toMatch(/^\$2[aby]\$10\$/);
  });

  it.each([
    ['email', 'email already in use'],
    ['username', 'username already in use'],
    ['something-else', 'field already in use'],
  ])('maps PG 23505 (%s) to a precise 409', async (detail, message) => {
    const service = makeService({
      create: async () => {
        const err: any = new Error('duplicate');
        err.code = '23505';
        err.detail = `Key (${detail}) already exists.`;
        throw err;
      },
    });
    const err = await service
      .register({ email: 'a@b.c', username: 'u', password: 'x'.repeat(8) } as any)
      .catch((e) => e);
    expect(err.status).toBe(409);
    expect(err.message).toBe(message);
  });

  it('rethrows non-unique persistence failures unwrapped', async () => {
    const service = makeService({
      create: async () => {
        throw new Error('connection reset');
      },
    });
    await expect(
      service.register({ email: 'a@b.c', username: 'u', password: 'x'.repeat(8) } as any),
    ).rejects.toThrow('connection reset');
  });
});

describe('AuthService.login (#308)', () => {
  it('returns tokens for valid credentials', async () => {
    const service = makeService({ findByEmail: async () => stored() });
    const res = await service.login({ email: 'alice@example.com', password: 'correct-horse' } as any);
    expect(res).toMatchObject({ userId: 'user-1' });
    expect(res.accessToken).toEqual(expect.any(String));
  });

  it('rejects unknown users without touching bcrypt compare', async () => {
    const service = makeService({ findByEmail: async () => null });
    const err = await service
      .login({ email: 'nobody@example.com', password: 'whatever12' } as any)
      .catch((e) => e);
    expect(err.status).toBe(401);
    expect(err.message).toBe('invalid credentials');
  });

  it('rejects wrong passwords with the same 401 (no user enumeration)', async () => {
    const service = makeService({ findByEmail: async () => stored() });
    const err = await service
      .login({ email: 'alice@example.com', password: 'wrong-pass' } as any)
      .catch((e) => e);
    expect(err.status).toBe(401);
    expect(err.message).toBe('invalid credentials');
  });
});

describe('AuthService.refresh (#308)', () => {
  const tokensFor = (sub: string, type: 'access' | 'refresh') =>
    new JwtService({ secret: 'test-secret-32-bytes-long-enough!!' }).sign({ sub, type });

  it('accepts a refresh token and rotates the pair shape', async () => {
    const service = makeService({ findById: async () => stored() });
    const res = await service.refresh({
      refreshToken: tokensFor('user-1', 'refresh'),
    } as any);
    expect(res).toMatchObject({ userId: 'user-1' });
  });

  it('rejects an access token used as a refresh token', async () => {
    const service = makeService({ findById: async () => stored() });
    const err = await service
      .refresh({ refreshToken: tokensFor('user-1', 'access') } as any)
      .catch((e) => e);
    expect(err.status).toBe(401);
    expect(err.message).toBe('refresh token required');
  });

  it('rejects malformed tokens and tokens for deleted users', async () => {
    const bad = makeService({ findById: async () => stored() });
    const malformed = await bad
      .refresh({ refreshToken: 'not-a-jwt' } as any)
      .catch((e) => e);
    expect(malformed.status).toBe(401);

    const gone = makeService({ findById: async () => null });
    const deleted = await gone
      .refresh({ refreshToken: tokensFor('ghost', 'refresh') } as any)
      .catch((e) => e);
    expect(deleted.status).toBe(401);
    expect(deleted.message).toBe('user no longer exists');
  });
});
