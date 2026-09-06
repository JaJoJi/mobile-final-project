import {
  CanActivate,
  ExecutionContext,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';

/**
 * REST JWT guard. Reads `Authorization: Bearer <token>`, verifies the
 * signature with the shared secret, attaches the decoded payload to
 * `request.user` for downstream handlers (e.g. `UserController`).
 *
 * Throws 401 on missing / malformed / invalid / expired token.
 *
 * Used by @UseGuards(JwtAccessGuard) on protected REST routes.
 */
@Injectable()
export class JwtAccessGuard implements CanActivate {
  private readonly logger = new Logger(JwtAccessGuard.name);

  constructor(private readonly jwt: JwtService) {}

  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest<{
      headers: Record<string, string | undefined>;
      user?: { sub: string; type: 'access' | 'refresh' };
    }>();

    const header = req.headers['authorization'];
    if (!header) {
      throw new UnauthorizedException('missing Authorization header');
    }
    const [scheme, token] = header.split(' ');
    if (scheme !== 'Bearer' || !token) {
      throw new UnauthorizedException('Authorization must be: Bearer <token>');
    }

    let payload: { sub: string; type: 'access' | 'refresh' };
    try {
      payload = this.jwt.verify(token);
    } catch (e) {
      throw new UnauthorizedException('invalid or expired token');
    }

    if (payload.type !== 'access') {
      throw new UnauthorizedException('access token required (got refresh?)');
    }

    req.user = payload;
    return true;
  }
}
