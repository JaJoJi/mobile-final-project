import { INestApplication } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';

/**
 * Mounts the auto-generated OpenAPI docs (P3-BE-03):
 *   - `GET /api/docs`  — Swagger UI
 *   - `GET /api/docs-json` — the raw OpenAPI 3 spec
 *
 * DTOs pick up `@ApiProperty()` metadata automatically via the
 * `class-validator` integration; no manual annotation needed for a first
 * pass.
 */
export function setupSwagger(app: INestApplication): void {
  const config = new DocumentBuilder()
    .setTitle('Auto Chess API')
    .setDescription('REST + WebSocket contract — see docs/04-api-contracts.md')
    .setVersion(process.env.npm_package_version ?? '0.1.0')
    .addBearerAuth()
    .build();

  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('api/docs', app, document, {
    jsonDocumentUrl: 'api/docs-json',
  });
}
