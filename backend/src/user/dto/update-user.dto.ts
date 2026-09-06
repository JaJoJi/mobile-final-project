import { IsString, MaxLength, MinLength, Matches } from 'class-validator';

/**
 * PATCH /user/me body — same username rules as register.
 */
export class UpdateUserDto {
  @IsString()
  @MinLength(3, { message: 'username must be at least 3 characters' })
  @MaxLength(20, { message: 'username must be at most 20 characters' })
  @Matches(/^[a-zA-Z0-9_]+$/, {
    message: 'username must be alphanumeric or underscore (no spaces)',
  })
  username!: string;
}
