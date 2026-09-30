import { IsNotEmpty, IsString } from 'class-validator';

/**
 * `POST /rooms/join` body (#258).
 *
 * Shape only — normalization (`trim` + uppercase) and the 6-char
 * `A-Z/2-9` charset check live in `RoomService` so the `room.invalid_code`
 * error code stays in one place.
 */
export class RoomJoinDto {
  @IsString()
  @IsNotEmpty()
  code!: string;
}
