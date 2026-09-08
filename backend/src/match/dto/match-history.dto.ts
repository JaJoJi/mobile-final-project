import { Type } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsISO8601,
  IsString,
  IsUUID,
  Min,
  ValidateIf,
  ValidateNested,
} from 'class-validator';
import { MatchStatus } from '../match.entity';

export type MatchOutcome = 'self' | 'opponent' | null;

export class MatchHistoryOpponentDto {
  @IsUUID('4')
  id!: string;

  @ValidateIf((_object, value) => value !== null)
  @IsString()
  username!: string | null;
}

/** One row returned by GET /match/history. */
export class MatchHistoryDto {
  @IsUUID('4')
  matchId!: string;

  @ValidateNested()
  @Type(() => MatchHistoryOpponentDto)
  opponent!: MatchHistoryOpponentDto;

  @IsIn(['self', 'opponent', null])
  winner!: MatchOutcome;

  @IsIn(['in_progress', 'finished', 'forfeited'])
  status!: MatchStatus;

  @IsInt()
  @Min(0)
  rounds!: number;

  @IsISO8601()
  createdAt!: string;

  @ValidateIf((_object, value) => value !== null)
  @IsInt()
  @Min(0)
  duration!: number | null;
}
