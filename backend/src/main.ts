import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { Logger, ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bufferLogs: false });
  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, transform: true, forbidNonWhitelisted: false }),
  );

  const port = parseInt(process.env.NEST_PORT ?? '3000', 10);
  await app.listen(port, '0.0.0.0');

  const instance = process.env.HOSTNAME ?? 'local';
  Logger.log(`Nest instance "${instance}" listening on :${port}`, 'Bootstrap');
}
bootstrap().catch((err) => {
  Logger.error(err, 'Bootstrap');
  process.exit(1);
});
