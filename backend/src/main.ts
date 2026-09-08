import 'reflect-metadata';
import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { setupSwagger } from './common/swagger';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bufferLogs: false });

  // Security headers (X-Content-Type-Options, X-Frame-Options, HSTS, …).
  // CSP is disabled — this process serves JSON + the Swagger UI only.
  app.use(helmet({ contentSecurityPolicy: false }));

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: false,
    }),
  );

  // Run every module's onModuleDestroy / onApplicationShutdown on SIGTERM /
  // SIGINT: Redis + BullMQ + the Pub/Sub subscriber all close cleanly.
  app.enableShutdownHooks();

  setupSwagger(app);

  const port = parseInt(process.env.NEST_PORT ?? '3000', 10);
  await app.listen(port, '0.0.0.0');

  const instance = process.env.HOSTNAME ?? 'local';
  Logger.log(`Nest instance "${instance}" listening on :${port}`, 'Bootstrap');
  Logger.log('OpenAPI docs at /api/docs', 'Bootstrap');
}

bootstrap().catch((err) => {
  Logger.error(err, 'Bootstrap');
  process.exit(1);
});
