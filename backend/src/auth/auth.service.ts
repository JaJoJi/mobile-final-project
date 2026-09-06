import {
  ConflictException,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { UserService } from '../user/user.service';
import { AuthResponse } from './dto/auth-response';
import { LoginDto } from './dto/login.dto';
import { RefreshDto } from './dto/refresh.dto';
import { RegisterDto } from './dto/register.dto';

/**
 * Auth business logic.
 *
 * Locked design (`docs/02-requirements.md`):
 *   - bcrypt cost 10
 *   - JWT access 7d, refresh 30d — both LONG-LIVED (no rotation per
 *     design decision; long-lived keeps refresh simpler)
 *   - no blacklist — logout = client deletes tokens
 *   - no rate limit — MVP only
 *
 * JWT payload shape: `{ sub: userId, type: 'access'|'refresh' }`.
 * Guards check `type` so an access token can't be used as refresh (and
 * vice versa).
 */
@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly users: UserService,
    private readonly jwt: JwtService,
  ) {}

  async register(dto: RegisterDto): Promise<AuthResponse> {
    const passwordHash = await bcrypt.hash(dto.password, 10);

    let user;
    try {
      user = await this.users.create({
        email: dto.email,
        username: dto.username,
        passwordHash,
      });
    } catch (e: any) {
      // PG unique-violation code 23505. The two unique constraints are
      // email and username — map both to a 409 with a precise field code.
      if (e?.code === '23505') {
        const detail: string = e?.detail ?? '';
        const field = detail.includes('email')
          ? 'email'
          : detail.includes('username')
            ? 'username'
            : 'field';
        throw new ConflictException(`${field} already in use`);
      }
      throw e;
    }

    this.logger.log(`registered user ${user.id} (${user.email})`);
    return {
      userId: user.id,
      ...this.signTokens(user.id),
    };
  }

  async login(dto: LoginDto): Promise<AuthResponse> {
    const user = await this.users.findByEmail(dto.email);
    if (!user) {
      throw new UnauthorizedException('invalid credentials');
    }

    const ok = await bcrypt.compare(dto.password, user.passwordHash);
    if (!ok) {
      throw new UnauthorizedException('invalid credentials');
    }

    return {
      userId: user.id,
      ...this.signTokens(user.id),
    };
  }

  async refresh(dto: RefreshDto): Promise<AuthResponse> {
    let payload: { sub: string; type: 'access' | 'refresh' };
    try {
      payload = this.jwt.verify(dto.refreshToken);
    } catch {
      throw new UnauthorizedException('invalid or expired refresh token');
    }

    if (payload.type !== 'refresh') {
      throw new UnauthorizedException('refresh token required');
    }

    // Verify the user still exists. (No blacklist per MVP design.)
    const user = await this.users.findById(payload.sub);
    if (!user) {
      throw new UnauthorizedException('user no longer exists');
    }

    return {
      userId: user.id,
      ...this.signTokens(user.id),
    };
  }

  // ─── helpers ──────────────────────────────────────────────────────

  private signTokens(userId: string): { accessToken: string; refreshToken: string } {
    const common = { sub: userId };
    const accessToken = this.jwt.sign(
      { ...common, type: 'access' },
      { expiresIn: process.env.JWT_ACCESS_TTL ?? '7d' },
    );
    const refreshToken = this.jwt.sign(
      { ...common, type: 'refresh' },
      { expiresIn: process.env.JWT_REFRESH_TTL ?? '30d' },
    );
    return { accessToken, refreshToken };
  }
}
