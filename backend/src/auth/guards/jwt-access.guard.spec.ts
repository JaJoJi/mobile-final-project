import { JwtService } from '@nestjs/jwt';
import * as jsonwebtoken from 'jsonwebtoken';
import { randomBytes } from 'crypto';
import { JwtAccessGuard } from './jwt-access.guard';

// Generated per run — never a hard-coded credential (Semgrep jwt-hardcode).
// Sign/verify round-trips only need both sides to share the value.
const SECRET = randomBytes(32).toString('hex');

const httpContext = (headers: Record<string, string | undefined>) =>
  ({
    switchToHttp: () => ({ getRequest: () => ({ headers }) }),
  }) as any;

const bearer = (token: string) => ({ authorization: `Bearer ${token}` });

describe('JwtAccessGuard (#308)', () => {
  const jwt = new JwtService({ secret: SECRET });
  const guard = new JwtAccessGuard(jwt);
  const access = (sub = 'user-1') => jwt.sign({ sub, type: 'access' });

  it('accepts a valid access token and attaches the payload', () => {
    const req: any = { headers: bearer(access()) };
    const ctx = { switchToHttp: () => ({ getRequest: () => req }) } as any;
    expect(guard.canActivate(ctx)).toBe(true);
    expect(req.user).toMatchObject({ sub: 'user-1', type: 'access' });
  });

  it('rejects missing and malformed Authorization headers with 401', () => {
    for (const headers of [{}, { authorization: 'Token abc' }, { authorization: 'Bearer ' }]) {
      expect(() => guard.canActivate(httpContext(headers))).toThrow(
        expect.objectContaining({ status: 401 }),
      );
    }
  });

  it('rejects tokens signed with a different secret', () => {
    const foreign = new JwtService({ secret: randomBytes(32).toString('hex') });
    const token = foreign.sign({ sub: 'user-1', type: 'access' });
    expect(() => guard.canActivate(httpContext(bearer(token)))).toThrow(
      expect.objectContaining({ status: 401 }),
    );
  });

  it('rejects expired tokens', () => {
    const expired = jsonwebtoken.sign(
      { sub: 'user-1', type: 'access', exp: Math.floor(Date.now() / 1000) - 60 },
      SECRET,
    );
    expect(() => guard.canActivate(httpContext(bearer(expired)))).toThrow(
      expect.objectContaining({ status: 401 }),
    );
  });

  it('rejects refresh tokens on access-guarded routes (type boundary)', () => {
    const refresh = jwt.sign({ sub: 'user-1', type: 'refresh' });
    expect(() => guard.canActivate(httpContext(bearer(refresh)))).toThrow(
      expect.objectContaining({ status: 401 }),
    );
  });
});
