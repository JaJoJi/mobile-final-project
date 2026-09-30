import { JwtService } from '@nestjs/jwt';
import * as jsonwebtoken from 'jsonwebtoken';
import { WsException } from '@nestjs/websockets';
import { WsAuthGuard } from './ws-auth.guard';

const SECRET = 'ws-guard-test-secret-32-bytes-long!';

const socketWith = (token: unknown) =>
  ({
    id: 'socket-1',
    data: {},
    handshake: { auth: { token } },
  }) as any;

describe('WsAuthGuard (#308)', () => {
  const jwt = new JwtService({ secret: SECRET });
  const guard = new WsAuthGuard(jwt);

  it('accepts a valid access token and populates client.data.user', () => {
    const client = socketWith(jwt.sign({ sub: 'user-9', type: 'access' }));
    expect(guard.authenticate(client)).toBe('user-9');
    expect(client.data.user).toMatchObject({ sub: 'user-9', type: 'access' });
  });

  it.each([[undefined], [null], [123]])(
    'rejects missing/non-string tokens as auth.invalid (%p)',
    (token) => {
      try {
        guard.authenticate(socketWith(token));
        throw new Error('should have thrown');
      } catch (e) {
        expect(e).toBeInstanceOf(WsException);
        expect((e as WsException).getError()).toBe('auth.invalid');
      }
    },
  );

  it('rejects bad signatures as auth.expired', () => {
    const foreign = new JwtService({ secret: 'different-secret-32-bytes!!!!!!' });
    const client = socketWith(foreign.sign({ sub: 'user-1', type: 'access' }));
    try {
      guard.authenticate(client);
      throw new Error('should have thrown');
    } catch (e) {
      expect((e as WsException).getError()).toBe('auth.expired');
    }
  });

  it('rejects genuinely expired tokens as auth.expired', () => {
    const expired = jsonwebtoken.sign(
      { sub: 'user-1', type: 'access', exp: Math.floor(Date.now() / 1000) - 60 },
      SECRET,
    );
    try {
      guard.authenticate(socketWith(expired));
      throw new Error('should have thrown');
    } catch (e) {
      expect((e as WsException).getError()).toBe('auth.expired');
    }
  });

  it.each([
    [{ sub: 'user-1', type: 'refresh' }],
    [{ sub: '', type: 'access' }],
    [{ type: 'access' }],
  ])('rejects wrong-type/ownerless payloads as auth.invalid (%p)', (payload) => {
    const client = socketWith(jwt.sign(payload));
    try {
      guard.authenticate(client);
      throw new Error('should have thrown');
    } catch (e) {
      expect((e as WsException).getError()).toBe('auth.invalid');
    }
  });

  it('canActivate delegates to the same path', () => {
    const client = socketWith(jwt.sign({ sub: 'user-1', type: 'access' }));
    const ctx = { switchToWs: () => ({ getClient: () => client }) } as any;
    expect(guard.canActivate(ctx)).toBe(true);
  });
});
