import { HttpException } from '@nestjs/common';
import type { DataSource } from 'typeorm';
import type { RedisService } from '../redis/redis.service';
import { HealthController } from './health.controller';

const makeController = (opts: { pg: boolean; redisPing: () => Promise<string> }) =>
  new HealthController(
    { isInitialized: opts.pg } as DataSource,
    { client: { ping: opts.redisPing } } as unknown as RedisService,
  );

describe('HealthController (P3-BE-03)', () => {
  it('/health/live is always 200 and never touches deps', async () => {
    const c = makeController({
      pg: false,
      redisPing: async () => {
        throw new Error('should not be called');
      },
    });
    expect(c.live()).toMatchObject({ status: 'live' });
  });

  it('/health/ready returns 200 when Postgres + Redis are up', async () => {
    const c = makeController({ pg: true, redisPing: async () => 'PONG' });
    await expect(c.ready()).resolves.toEqual({ status: 'ready' });
  });

  it('/health/ready throws 503 when Redis is down', async () => {
    const c = makeController({
      pg: true,
      redisPing: async () => {
        throw new Error('ECONNREFUSED');
      },
    });
    await expect(c.ready()).rejects.toMatchObject({
      status: 503,
      response: { status: 'not_ready', redis: false },
    });
  });

  it('/health/ready throws 503 when Postgres is not initialised', async () => {
    const c = makeController({ pg: false, redisPing: async () => 'PONG' });
    await expect(c.ready()).rejects.toBeInstanceOf(HttpException);
  });

  it('/health aggregate reports degraded when a dep is down', async () => {
    const c = makeController({ pg: true, redisPing: async () => 'NOPE' });
    const body = await c.getHealth();
    expect(body).toMatchObject({ status: 'degraded', postgres: 'up', redis: 'down' });
  });
});
