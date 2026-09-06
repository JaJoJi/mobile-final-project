import { IsEmail, IsString, MinLength, MaxLength, Matches } from 'class-validator';

/**
 * POST /auth/register payload.
 *
 * Rules locked in `docs/02-requirements.md` FR-AUTH-1 and the design
 * decision "3–20 chars, alphanumeric + underscore, unique".
 */
export class RegisterDto {
  @IsEmail({}, { message: 'email must be a valid email address' })
  email!: string;

  @IsString()
  @MinLength(3, { message: 'username must be at least 3 characters' })
  @MaxLength(20, { message: 'username must be at most 20 characters' })
  @Matches(/^[a-zA-Z0-9_]+$/, {
    message: 'username must be alphanumeric or underscore (no spaces)',
  })
  username!: string;

  @IsString()
  @MinLength(8, { message: 'password must be at least 8 characters' })
  password!: string;
}
