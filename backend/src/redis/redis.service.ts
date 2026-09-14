import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import Redis from 'ioredis';
import { LUA_SCRIPTS } from './scripts';

@Injectable()
export class RedisService implements OnModuleDestroy, OnModuleInit {
  private readonly logger = new Logger(RedisService.name);
  public readonly client: Redis;
  /**
   * Separate connection for BullMQ workers. BullMQ requires
   * `maxRetriesPerRequest: null` because workers issue blocking commands
   * (BRPOPLPUSH / BLPOP / XREAD BLOCK ...) — a positive
   * `maxRetriesPerRequest` causes the runtime to reject the options.
   * Producers don't block, so they share `client`; only workers use this.
   */
  public readonly bullClient: Redis;
  private readonly shaCache = new Map<string, string>();

  constructor() {
    const url = process.env.REDIS_URL ?? 'redis://localhost:6379';
    const baseOpts = {
      enableReadyCheck: true,
      lazyConnect: false,
      retryStrategy: (times: number) => Math.min(times * 200, 2000),
    };
    this.client = new Redis(url, { ...baseOpts, maxRetriesPerRequest: 3 });
    this.bullClient = new Redis(url, { ...baseOpts, maxRetriesPerRequest: null });
    const onError = (e: Error) => this.logger.error(`redis error: ${e.message}`);
    const onConnect = () => this.logger.log(`connected to ${url}`);
    this.client.on('error', onError);
    this.client.on('connect', onConnect);
    this.bullClient.on('error', onError);
    this.bullClient.on('connect', onConnect);
  }

  async onModuleInit() {
    // RedisService.client is constructed eagerly (see constructor) so that
    // synchronous consumers like BullModule.registerQueueAsync can read it
    // during module instantiation. Here we wait for the connection to be
    // ready and load Lua scripts.
    await this.client.ping();
    await this.loadScripts();
  }

  async onModuleDestroy() {
    await Promise.allSettled([this.client?.quit(), this.bullClient?.quit()]);
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

