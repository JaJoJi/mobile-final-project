import { Controller, Get } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';
import { RedisService } from '../redis/redis.service';

@Controller('health')
export class HealthController {
  constructor(
    @InjectDataSource() private readonly dataSource: DataSource,
    private readonly redis: RedisService,
  ) {}

  @Get()
  async getHealth() {
    const pgUp = this.dataSource.isInitialized;
    let redisUp = false;
    let redisError: string | undefined;
    try {
      const res = await this.redis.client.ping();
      redisUp = res === 'PONG';
    } catch (e: any) {
      redisError = e?.message ?? String(e);
    }

    const ok = pgUp && redisUp;
    return {
      status: ok ? 'ok' : 'degraded',
      postgres: pgUp ? 'up' : 'down',
      redis: redisUp ? 'up' : 'down',
      redisError,
      instance: process.env.HOSTNAME ?? 'local',
      timestamp: new Date().toISOString(),
    };
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
}

