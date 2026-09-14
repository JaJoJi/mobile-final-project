import { Controller, Get, HttpCode, HttpException } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';
import { RedisService } from '../redis/redis.service';

@Controller('health')
export class HealthController {
  constructor(
    @InjectDataSource() private readonly dataSource: DataSource,
    private readonly redis: RedisService,
  ) {}

  /** Backwards-compatible aggregate check (used by the mobile smoke screen). */
  @Get()
  async getHealth() {
    const deps = await this.checkDeps();
    return {
      status: deps.ok ? 'ok' : 'degraded',
      postgres: deps.postgres ? 'up' : 'down',
      redis: deps.redis ? 'up' : 'down',
      redisError: deps.redisError,
      instance: process.env.HOSTNAME ?? 'local',
      timestamp: new Date().toISOString(),
    };
  }

  /**
   * Liveness — is the process up at all? Always 200 while the event loop
   * runs. A failing `/live` tells an orchestrator to restart the pod.
   */
  @Get('live')
  @HttpCode(200)
  live() {
    return { status: 'live', instance: process.env.HOSTNAME ?? 'local' };
  }

  /**
   * Readiness — can this instance serve traffic? 200 only when Postgres
   * and Redis are both reachable, otherwise 503 so the load balancer
   * stops routing to it (without killing it).
   */
  @Get('ready')
  async ready() {
    const deps = await this.checkDeps();
    if (!deps.ok) {
      throw new HttpException(
        { status: 'not_ready', postgres: deps.postgres, redis: deps.redis },
        503,
      );
    }
    return { status: 'ready' };
  }

  @Get('whoami')
  whoami() {
    return {
      instance: process.env.HOSTNAME ?? 'local',
      pid: process.pid,
      uptime: process.uptime(),
      timestamp: new Date().toISOString(),
    };
  }

  private async checkDeps(): Promise<{
    ok: boolean;
    postgres: boolean;
    redis: boolean;
    redisError?: string;
  }> {
    const postgres = this.dataSource.isInitialized;
    let redis = false;
    let redisError: string | undefined;
    try {
      redis = (await this.redis.client.ping()) === 'PONG';
    } catch (e: unknown) {
      redisError = e instanceof Error ? e.message : String(e);
    }
    return { ok: postgres && redis, postgres, redis, redisError };
  }
}
