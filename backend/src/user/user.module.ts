import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JwtAuthModule } from '../common/jwt-auth.module';
import { StatsService } from './stats.service';
import { UserController } from './user.controller';
import { User } from './user.entity';
import { UserService } from './user.service';

/**
 * User module.
 *
 * Imports JwtAuthModule so UserController can apply JwtAccessGuard on
 * its protected routes.
 *
 * Exports UserService so AuthModule can use it for register/login/refresh
 * (avoiding two repositories reaching the same table from different
 * modules). Exports StatsService so MatchModule can invalidate the stats
 * cache on finalization (no module cycle: UserModule never imports
 * MatchModule; StatsService reads matches via DataSource, not the
 * MatchModule providers).
 */
@Module({
  imports: [TypeOrmModule.forFeature([User]), JwtAuthModule],
  controllers: [UserController],
  providers: [UserService, StatsService],
  exports: [UserService, StatsService],
})
export class UserModule {}
