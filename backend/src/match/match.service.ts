import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { DataSource } from 'typeorm';
import { PubsubBridge } from '../runtime/pubsub.bridge';
import { UserService } from '../user/user.service';
import { MatchDetailDto } from './dto/match-detail.dto';
import { MatchHistoryDto, MatchOutcome } from './dto/match-history.dto';
import { Match, MatchStatus } from './match.entity';
import { MatchRepository } from './match.repository';

export type MatchEndReason = 'hp_zero' | 'forfeit' | 'disconnect';

const ELO_K_FACTOR = 32;
const HISTORY_LIMIT = 50;

@Injectable()
export class MatchService {
  private readonly logger = new Logger(MatchService.name);

  constructor(
    private readonly dataSource: DataSource,
    private readonly matches: MatchRepository,
    private readonly pubsub: PubsubBridge,
    private readonly users: UserService,
  ) {}

  async findById(id: string): Promise<Match> {
    const match = await this.matches.findById(id);
    if (!match) this.throwNotFound(id);
    return match;
  }

  async updateState(
    matchId: string,
    side: 'p1' | 'p2',
    state: Record<string, unknown>,
  ): Promise<void> {
    const updated = await this.matches.updateState(matchId, side, state);
    if (!updated) this.throwNotFound(matchId);
  }

  async updateRuntimeSnapshot(
    matchId: string,
    input: {
      p1State: Record<string, unknown>;
      p2State: Record<string, unknown>;
      wipeIndexP1: number;
      wipeIndexP2: number;
    },
  ): Promise<void> {
    const updated = await this.matches.updateRuntimeSnapshot(matchId, input);
    if (!updated) this.throwNotFound(matchId);
  }

  async forfeitDisconnectedPlayer(matchId: string, userId: string): Promise<boolean> {
    const match = await this.matches.findById(matchId);
    if (!match || match.status !== 'in_progress') return false;
    if (userId !== match.player1Id && userId !== match.player2Id) return false;
    const winnerId = userId === match.player1Id ? match.player2Id : match.player1Id;
    return this.finalize(match.id, winnerId, 'disconnect');
  }

  async appendRoundEvents(
    matchId: string,
    roundNumber: number,
    events: Record<string, unknown>[],
  ): Promise<void> {
    if (!Number.isInteger(roundNumber) || roundNumber < 1) {
      throw new BadRequestException({
        code: 'match.invalid_round',
        message: 'roundNumber must be an integer greater than zero',
      });
    }

    await this.dataSource.transaction(async (manager) => {
      const match = await this.matches.findByIdForUpdate(matchId, manager);
      if (!match) this.throwNotFound(matchId);
      await this.matches.saveRoundEvents(matchId, roundNumber, events, manager);
    });
  }

  /**
   * Finish a match exactly once. The match row and both ELO updates share one
   * transaction, so concurrent hp/disconnect signals cannot award rating twice.
   */
  async finalize(
    matchId: string,
    winnerId: string | null,
    reason: MatchEndReason,
  ): Promise<boolean> {
    let finalized: Match | null = null;

    await this.dataSource.transaction(async (manager) => {
      const match = await this.matches.findByIdForUpdate(matchId, manager);
      if (!match) this.throwNotFound(matchId);
      if (match.status !== 'in_progress') return;
      if (winnerId && winnerId !== match.player1Id && winnerId !== match.player2Id) {
        throw new BadRequestException({
          code: 'match.invalid_winner',
          message: 'winnerId must be one of the match participants',
        });
      }

      if (winnerId) {
        const players = await this.users.findByIdsForUpdate(
          [match.player1Id, match.player2Id],
          manager,
        );
        if (players.length !== 2) {
          throw new NotFoundException({
            code: 'match.player_not_found',
            message: 'One or more match participants no longer exist',
          });
        }
        const p1 = players.find((player) => player.id === match.player1Id)!;
        const p2 = players.find((player) => player.id === match.player2Id)!;
        const p1Delta = this.eloDelta(p1.rating, p2.rating, winnerId === p1.id ? 1 : 0);
        await this.users.updateRating(p1.id, p1Delta, manager);
        await this.users.updateRating(p2.id, -p1Delta, manager);
      }

      const status: MatchStatus = reason === 'hp_zero' ? 'finished' : 'forfeited';
      const finishedAt = new Date();
      await this.matches.finalize(
        match,
        { status, winnerId, finishedAt },
        manager,
      );
      finalized = Object.assign(match, { status, winnerId, finishedAt });
    });

    if (!finalized) return false;
    await this.pubsub.publish(finalized.id, 'game:match:end', {
      matchId: finalized.id,
      winnerId: finalized.winnerId,
      reason,
      final: {
        p1: this.finalPlayerState(finalized.p1State),
        p2: this.finalPlayerState(finalized.p2State),
      },
    });
    this.logger.log(
      `finalized match=${finalized.id} winner=${finalized.winnerId ?? 'draw'} reason=${reason}`,
    );
    return true;
  }

  /** Finds the active match; RuntimeAdapter closes its Redis phase before calling this. */
  async leaveMatch(userId: string): Promise<boolean> {
    const match = await this.matches.findActiveByUserId(userId);
    if (!match) return false;
    return this.forfeitDisconnectedPlayer(match.id, userId);
  }

  async getHistory(userId: string): Promise<MatchHistoryDto[]> {
    const matches = await this.matches.findHistoryByUserId(userId, HISTORY_LIMIT);
    const opponentIds = matches.map((match) =>
      match.player1Id === userId ? match.player2Id : match.player1Id,
    );
    const [opponents, roundCounts] = await Promise.all([
      this.users.findByIds([...new Set(opponentIds)]),
      this.matches.countRoundsByMatchIds(matches.map((match) => match.id)),
    ]);
    const usernames = new Map(opponents.map((user) => [user.id, user.username]));

    return matches.map((match, index) => ({
      matchId: match.id,
      opponent: {
        id: opponentIds[index],
        username: usernames.get(opponentIds[index]) ?? null,
      },
      winner: this.outcomeFor(match, userId),
      status: match.status,
      rounds: roundCounts.get(match.id) ?? 0,
      createdAt: match.createdAt.toISOString(),
      duration: match.finishedAt
        ? Math.max(0, Math.floor((match.finishedAt.getTime() - match.createdAt.getTime()) / 1000))
        : null,
    }));
  }

  async getDetail(matchId: string, userId: string): Promise<MatchDetailDto> {
    const match = await this.findById(matchId);
    if (match.player1Id !== userId && match.player2Id !== userId) {
      throw new ForbiddenException({
        code: 'match.not_your_match',
        message: 'You are not a participant in this match',
      });
    }

    const [players, rounds] = await Promise.all([
      this.users.findByIds([match.player1Id, match.player2Id]),
      this.matches.findRounds(match.id),
    ]);
    const usernames = new Map(players.map((player) => [player.id, player.username]));

    return {
      matchId: match.id,
      players: [match.player1Id, match.player2Id].map((id) => ({
        id,
        username: usernames.get(id) ?? null,
      })),
      winnerId: match.winnerId,
      winner: match.winnerId ? usernames.get(match.winnerId) ?? null : null,
      status: match.status,
      rounds: rounds.map((round) => ({
        roundNumber: round.roundNumber,
        events: round.events,
      })),
      createdAt: match.createdAt.toISOString(),
      finishedAt: match.finishedAt?.toISOString() ?? null,
    };
  }

  private outcomeFor(match: Match, userId: string): MatchOutcome {
    if (!match.winnerId) return null;
    return match.winnerId === userId ? 'self' : 'opponent';
  }

  private eloDelta(rating: number, opponentRating: number, score: 0 | 1): number {
    const expected = 1 / (1 + 10 ** ((opponentRating - rating) / 400));
    return Math.round(ELO_K_FACTOR * (score - expected));
  }

  private finalPlayerState(state: Record<string, unknown>): { hp: number; gold: number } {
    return {
      hp: typeof state.hp === 'number' ? state.hp : 0,
      gold: typeof state.gold === 'number' ? state.gold : 0,
    };
  }

  private throwNotFound(matchId: string): never {
    throw new NotFoundException({
      code: 'match.not_found',
      message: `Match ${matchId} not found`,
    });
  }
}
