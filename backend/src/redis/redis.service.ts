import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import Redis from 'ioredis';
import { LUA_SCRIPTS } from './scripts';

@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);
  public client: Redis;
  private shaCache = new Map<string, string>();

  async onModuleInit() {
    const url = process.env.REDIS_URL ?? 'redis://localhost:6379';
    this.client = new Redis(url, {
      maxRetriesPerRequest: 3,
      enableReadyCheck: true,
      lazyConnect: false,
      retryStrategy: (times) => Math.min(times * 200, 2000),
    });
    this.client.on('error', (e) => this.logger.error(`redis error: ${e.message}`));
    this.client.on('connect', () => this.logger.log(`connected to ${url}`));

    await this.client.ping();
    await this.loadScripts();
  }

  async onModuleDestroy() {
    await this.client?.quit();
  }

  private async loadScripts(): Promise<void> {
    for (const [name, source] of Object.entries(LUA_SCRIPTS)) {
      const sha = (await this.client.script('LOAD', source)) as string;
      this.shaCache.set(name, sha);
    }
    this.logger.log(`Loaded ${this.shaCache.size} Lua scripts`);
  }

  async eval<T = unknown>(scriptName: string, keys: string[], args: (string | number)[]): Promise<T> {
    const source = LUA_SCRIPTS[scriptName];
    if (!source) throw new Error(`Unknown Lua script: ${scriptName}`);

    const cachedSha = this.shaCache.get(scriptName);
    try {
      return (await this.client.evalsha(
        cachedSha,
        keys.length,
        ...keys,
        ...args.map((a) => String(a)),
      )) as T;
    } catch (e: any) {
      if (typeof e?.message === 'string' && e.message.includes('NOSCRIPT')) {
        const newSha = (await this.client.script('LOAD', source)) as string;
        this.shaCache.set(scriptName, newSha);
        return (await this.client.evalsha(
          newSha,
          keys.length,
          ...keys,
          ...args.map((a) => String(a)),
        )) as T;
      }
      throw e;
    }
  }

  getScriptSha(scriptName: string): string | undefined {
    return this.shaCache.get(scriptName);
  }
}
