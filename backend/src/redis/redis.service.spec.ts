// ioredis opens real sockets in the service constructor, so the module is
// stubbed and each construction is captured for option assertions.
const instances: Array<{ url: unknown; opts: Record<string, unknown>; handlers: Record<string, Array<(...args: any[]) => void>> }> = [];
jest.mock('ioredis', () => ({
  __esModule: true,
  default: class FakeRedis {
    public calls: Array<{ method: string; args: unknown[] }> = [];
    public evalshaImpl: ((...args: any[]) => Promise<unknown>) | null = null;
    public scriptImpl: ((...args: any[]) => Promise<unknown>) | null = null;
    public pingImpl: (() => Promise<unknown>) | null = null;
    private handlers: Record<string, Array<(...args: any[]) => void>> = {};

    constructor(
      public url: unknown,
      public opts: Record<string, unknown>,
    ) {
      instances.push({ url, opts, handlers: this.handlers });
    }

    on(event: string, handler: (...args: any[]) => void): this {
      (this.handlers[event] ??= []).push(handler);
      return this;
    }

    async ping(...args: unknown[]): Promise<unknown> {
      this.calls.push({ method: 'ping', args });
      if (this.pingImpl) return this.pingImpl();
      return 'PONG';
    }

    async script(...args: unknown[]): Promise<unknown> {
      this.calls.push({ method: 'script', args });
      if (this.scriptImpl) return this.scriptImpl(...args);
      return `sha-for-${String(args[1]).slice(0, 8)}`;
    }

    async evalsha(...args: unknown[]): Promise<unknown> {
      this.calls.push({ method: 'evalsha', args });
      if (this.evalshaImpl) return this.evalshaImpl(...args);
      return 1;
    }

    async quit(): Promise<unknown> {
      this.calls.push({ method: 'quit', args: [] });
      return 'OK';
    }
  },
}));

import { LUA_SCRIPTS } from './scripts';
import { RedisService } from './redis.service';

beforeEach(() => {
  instances.length = 0;
  delete process.env.REDIS_URL;
});

function service() {
  const svc = new RedisService();
  const client = (svc as any).client;
  const bull = (svc as any).bullClient;
  return { svc, client, bull };
}

describe('RedisService construction (#309)', () => {
  it('opens a command client and a blocking worker client with distinct retry policies', () => {
    process.env.REDIS_URL = 'redis://test:6379';
    service();
    expect(instances).toHaveLength(2);
    expect(instances[0].url).toBe('redis://test:6379');
    expect(instances[0].opts).toMatchObject({ maxRetriesPerRequest: 3 });
    expect(instances[1].opts).toMatchObject({ maxRetriesPerRequest: null });
  });

  it('registers error/connect handlers on both connections', () => {
    service();
    expect(instances).toHaveLength(2);
    for (const inst of instances) {
      expect(Object.keys(inst.handlers)).toEqual(
        expect.arrayContaining(['error', 'connect']),
      );
    }
  });
});

describe('RedisService script lifecycle (#309)', () => {
  it('pings then loads every Lua script on init and caches SHAs', async () => {
    const { svc, client } = service();
    await svc.onModuleInit();
    expect(client.calls[0]).toMatchObject({ method: 'ping' });
    const loads = client.calls.filter((c: any) => c.method === 'script');
    expect(loads).toHaveLength(Object.keys(LUA_SCRIPTS).length);
    for (const name of Object.keys(LUA_SCRIPTS)) {
      expect(svc.getScriptSha(name)).toEqual(expect.any(String));
    }
    expect(svc.getScriptSha('nope')).toBeUndefined();
  });

  it('evals by cached SHA with stringified args', async () => {
    const { svc, client } = service();
    await svc.onModuleInit();
    const sha = svc.getScriptSha('phase_flip');
    await svc.eval('phase_flip', ['k1'], ['a', 2]);
    const call = client.calls.find((c: any) => c.method === 'evalsha');
    expect(call?.args).toEqual([sha, 1, 'k1', 'a', '2']);
  });

  it('reloads on NOSCRIPT and retries with the fresh SHA', async () => {
    const { svc, client } = service();
    await svc.onModuleInit();
    let attempts = 0;
    client.evalshaImpl = async (...args: any[]) => {
      attempts += 1;
      if (attempts === 1) {
        const err = new Error('NOSCRIPT No matching script. Please use EVAL.');
        throw err;
      }
      return `ok-with-${args[0]}`;
    };
    client.scriptImpl = async () => 'fresh-sha';
    const res = await svc.eval('combat_done', ['k'], ['u1']);
    expect(res).toBe('ok-with-fresh-sha');
    expect(svc.getScriptSha('combat_done')).toBe('fresh-sha');
  });

  it('rethrows non-NOSCRIPT eval errors without reloading', async () => {
    const { svc, client } = service();
    await svc.onModuleInit();
    const loadsBefore = client.calls.filter((c: any) => c.method === 'script').length;
    client.evalshaImpl = async () => {
      throw new Error('CLUSTERDOWN');
    };
    await expect(svc.eval('phase_flip', ['k'], [])).rejects.toThrow('CLUSTERDOWN');
    expect(client.calls.filter((c: any) => c.method === 'script')).toHaveLength(loadsBefore);
  });

  it('rejects unknown script names before touching Redis', async () => {
    const { svc, client } = service();
    await expect(svc.eval('missing', [], [])).rejects.toThrow(
      'Unknown Lua script: missing',
    );
    expect(client.calls.filter((c: any) => c.method === 'evalsha')).toHaveLength(0);
  });

  it('quits both connections on destroy, tolerating single failures', async () => {
    const { svc, client, bull } = service();
    client.quit = async () => {
      throw new Error('already gone');
    };
    await expect(svc.onModuleDestroy()).resolves.toBeUndefined();
    expect(bull.calls.filter((c: any) => c.method === 'quit')).toHaveLength(1);
  });
});
