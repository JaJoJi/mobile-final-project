import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { join } from 'path';
import { AuthModule } from './auth/auth.module';
import { HealthController } from './common/health.controller';
import { ENTITIES } from './database/entities';
import { QueueModule } from './queue/queue.module';
import { RedisModule } from './redis/redis.module';
import { RedisService } from './redis/redis.service';
import { UserModule } from './user/user.module';

@Module({
  imports: [
    TypeOrmModule.forRootAsync({
      useFactory: () => ({
        type: 'postgres',
        url: process.env.DATABASE_URL,
        entities: ENTITIES,
        // Migrations are compiled to dist/migrations/*.js by `npm run build`.
        migrations: [join(__dirname, 'migrations', '*.js')],
        // Only ONE Nest instance should run migrations on boot, to avoid
        // races (multiple workers trying to ALTER the same table).
        // nest-1 has RUN_MIGRATIONS=true; nest-2/3 have it unset (=false).
        migrationsRun: process.env.RUN_MIGRATIONS === 'true',
        // Migrations are the source of truth — never auto-sync schemas.
        synchronize: false,
        retryAttempts: 10,
        retryDelay: 2000,
        logging: ['error', 'warn', 'migration'],
      }),
    }),
    RedisModule,
    QueueModule,
    UserModule,
    AuthModule,
  ],
  controllers: [HealthController],
  providers: [RedisService],
})
export class AppModule {}

