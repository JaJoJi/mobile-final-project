import { Type } from 'class-transformer';
import {
  IsArray,
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

export class MatchPlayerDto {
  @IsUUID('4')
  id!: string;

  @ValidateIf((_object, value) => value !== null)
  @IsString()
  username!: string | null;
}

export class MatchRoundDto {
  @IsInt()
  @Min(1)
  roundNumber!: number;

  @IsArray()
  events!: Record<string, unknown>[];
}

/** Full replay-oriented response returned by GET /match/:matchId. */
export class MatchDetailDto {
  @IsUUID('4')
  matchId!: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => MatchPlayerDto)
  players!: MatchPlayerDto[];

  @ValidateIf((_object, value) => value !== null)
  @IsUUID('4')
  winnerId!: string | null;

  @ValidateIf((_object, value) => value !== null)
  @IsString()
  winner!: string | null;

  @IsIn(['in_progress', 'finished', 'forfeited'])
  status!: MatchStatus;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => MatchRoundDto)
  rounds!: MatchRoundDto[];

  @IsISO8601()
  createdAt!: string;

  @ValidateIf((_object, value) => value !== null)
  @IsISO8601()
  finishedAt!: string | null;
}
