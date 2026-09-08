import {
  ArgumentMetadata,
  Injectable,
  PipeTransform,
} from '@nestjs/common';
import { WsException } from '@nestjs/websockets';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';

/**
 * Validation pipe for WS message payloads.
 *
 * Applied on `@SubscribeMessage` handlers (P0-BE-10) so a malformed
 * client message is rejected *before* the handler runs — it can't crash
 * a handler or write garbage to Redis (`NFR-6`).
 *
 * Behaviour:
 *   - Non-class metatypes (String, Number, raw Object, …) pass straight
 *     through — only decorated DTO classes are validated.
 *   - `whitelist: true` strips any property the DTO didn't declare, so a
 *     client can't smuggle extra fields into downstream logic.
 *   - `forbidNonWhitelisted: false` — extra fields are dropped silently
 *     rather than turned into an error (more forgiving to client version
 *     skew; the stripped value never reaches a handler anyway).
 *   - On failure throws `WsException` with `{ code: 'invalid_payload',
 *     message }`. The WS exception layer forwards that to the client;
 *     the shape mirrors `game:error` (`docs/04-api-contracts.md §2.1`)
 *     and the stable-code convention used by `WsAuthGuard`.
 */
@Injectable()
export class WsValidationPipe implements PipeTransform {
  async transform(value: unknown, { metatype }: ArgumentMetadata): Promise<unknown> {
    if (!metatype || !this.shouldValidate(metatype)) {
      return value;
    }

    // socket.io hands us already-parsed JSON; a non-object payload
    // (null, string, array) can't map onto a DTO — reject early.
    const raw =
      value === null || typeof value !== 'object' || Array.isArray(value)
        ? {}
        : (value as Record<string, unknown>);

    const instance = plainToInstance(metatype, raw);
    const errors = await validate(instance as object, {
      whitelist: true,
      forbidNonWhitelisted: false,
      // `instance` is always a real class instance built by
      // `plainToInstance` above, so the raw-object attack that
      // `forbidUnknownValues` guards against can't happen here. Turning
      // it off lets the no-field DTOs (MatchmakingJoin/Leave) validate
      // instead of throwing "an unknown value was passed".
      forbidUnknownValues: false,
    });

    if (errors.length > 0) {
      const first =
        errors
          .flatMap((e) => Object.values(e.constraints ?? {}))
          .find(Boolean) ?? 'payload failed validation';
      throw new WsException({ code: 'invalid_payload', message: first });
    }

    return instance;
  }

  private shouldValidate(metatype: ArgumentMetadata['metatype']): boolean {
    const primitives: unknown[] = [String, Boolean, Number, Array, Object];
    return !primitives.includes(metatype);
  }
}
