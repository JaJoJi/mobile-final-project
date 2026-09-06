import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { JwtAccessGuard } from '../auth/guards/jwt-access.guard';

/**
 * Shared JWT module — provides `JwtService` and `JwtAccessGuard` to
 * any module that imports it.
 *
 * Why this exists: AuthModule and UserModule both need JwtAccessGuard
 * for protected routes. If UserModule imports AuthModule to get it,
 * and AuthModule imports UserModule to get UserService, we have a
 * circular dependency. This module breaks that cycle.
 */
@Module({
  imports: [
    JwtModule.registerAsync({
      useFactory: () => ({
        secret: process.env.JWT_SECRET,
        signOptions: { algorithm: 'HS256' },
        verifyOptions: { algorithms: ['HS256'] },
      }),
    }),
  ],
  providers: [JwtAccessGuard],
  exports: [JwtModule, JwtAccessGuard],
})
export class JwtAuthModule {}
