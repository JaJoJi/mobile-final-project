import { IsJWT } from 'class-validator';

export class RefreshDto {
  @IsJWT({ message: 'refreshToken must be a valid JWT' })
  refreshToken!: string;
}
