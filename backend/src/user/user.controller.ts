import {
  ConflictException,
  Controller,
  Get,
  Patch,
  Body,
  UseGuards,
} from '@nestjs/common';
import { JwtAccessGuard } from '../auth/guards/jwt-access.guard';
import { CurrentUser } from './decorators/current-user.decorator';
import { UpdateUserDto } from './dto/update-user.dto';
import { UserService } from './user.service';

/**
 * GET /user/me, PATCH /user/me.
 *
 * Locked design (`docs/04-api-contracts.md`):
 *   - GET  → `{ id, email, username, rating }`
 *   - PATCH → updates `username` only (email + password non-editable)
 *   - 401 on missing / invalid token (handled by JwtAccessGuard)
 */
@Controller('user')
@UseGuards(JwtAccessGuard)
export class UserController {
  constructor(private readonly users: UserService) {}

  @Get('me')
  async me(@CurrentUser() jwt: { sub: string; type: string }) {
    const user = await this.users.findById(jwt.sub);
    if (!user) {
      throw new ConflictException('user not found');
    }
    return {
      id: user.id,
      email: user.email,
      username: user.username,
      rating: user.rating,
    };
  }

  @Patch('me')
  async updateMe(
    @CurrentUser() jwt: { sub: string; type: string },
    @Body() dto: UpdateUserDto,
  ) {
    try {
      const updated = await this.users.updateUsername(jwt.sub, dto.username);
      return {
        id: updated.id,
        email: updated.email,
        username: updated.username,
        rating: updated.rating,
      };
    } catch (e: any) {
      // PG 23505 = unique violation on username
      if (e?.code === '23505') {
        throw new ConflictException('username already in use');
      }
      throw e;
    }
  }
}
