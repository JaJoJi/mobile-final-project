import { Module } from '@nestjs/common';
import { UserModule } from '../user/user.module';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtAuthModule } from '../common/jwt-auth.module';

/**
 * Auth module.
 *
 * Imports:
 *   - UserModule — for UserService (single repository owner for users).
 *   - JwtAuthModule — for JwtService + JwtAccessGuard. Imported here
 *     so AuthController routes that need to verify tokens (none yet,
 *     but reserved for future /auth/me) can use JwtAccessGuard. The
 *     same JwtAuthModule is also imported by UserModule — sharing via
 *     a common module avoids the AuthModule ⇄ UserModule cycle.
 *
 * Exports: AuthService (rarely needed externally).
 */
@Module({
  imports: [UserModule, JwtAuthModule],
  controllers: [AuthController],
  providers: [AuthService],
  exports: [AuthService],
})
export class AuthModule {}
