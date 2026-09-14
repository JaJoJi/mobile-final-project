import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { EntityManager, Repository } from 'typeorm';
import { Match, MatchStatus } from './match.entity';
import { MatchRound } from './match-round.entity';

/**
 * Data access for the `matches` table.
 *
 * Thin wrapper over `Repository<Match>` — keeps query logic out of the
 * service / orchestrator layers (P0-BE-12, P0-BE-13) so DB shapes
 * never leak past this seam. Namesake follows the issue spec for
 * P0-BE-07 (diverges from the `UserService` naming but is intentional
 * — the orchestrator owns match lifecycle, this layer is just IO).
 *
 * Lifecycle mutations are exposed as small repository methods so
 * P0-BE-12's `MatchService` and P0-BE-13's orchestrator can compose
 * them inside shared `EntityManager` transactions without leaking
 * TypeORM queries into the domain layer.
 */
@Injectable()
export class MatchRepository {
  constructor(
    @InjectRepository(Match)
    private readonly repo: Repository<Match>,
    @InjectRepository(MatchRound)
    private readonly roundRepo: Repository<MatchRound>,
  ) {}

  private matches(manager?: EntityManager): Repository<Match> {
    return manager?.getRepository(Match) ?? this.repo;
  }

  private rounds(manager?: EntityManager): Repository<MatchRound> {
    return manager?.getRepository(MatchRound) ?? this.roundRepo;
  }

  /**
   * Insert a new match row. Caller provides `player1Id`, `player2Id`,
   * `matchSeed`, and the initial `p1State` / `p2State` snapshots.
   * `status`, `wipeIndexP1`, `wipeIndexP2`, `winnerId`, `finishedAt`
   * fall back to entity defaults (or `null`).
   */
  create(input: {
    player1Id: string;
    player2Id: string;
    matchSeed: string;
    p1State: Record<string, unknown>;
    p2State: Record<string, unknown>;
    status?: MatchStatus;
    wipeIndexP1?: number;
    wipeIndexP2?: number;
  }): Promise<Match> {
    const partial: Partial<Match> = {
      player1Id: input.player1Id,
      player2Id: input.player2Id,
      matchSeed: input.matchSeed,
      p1State: input.p1State,
      p2State: input.p2State,
    };
    if (input.status !== undefined) partial.status = input.status;
    if (input.wipeIndexP1 !== undefined) partial.wipeIndexP1 = input.wipeIndexP1;
    if (input.wipeIndexP2 !== undefined) partial.wipeIndexP2 = input.wipeIndexP2;
    return this.repo.save(this.repo.create(partial));
  }

  /** Primary-key lookup; returns `null` if not found. */
  findById(id: string, manager?: EntityManager): Promise<Match | null> {
    return this.matches(manager).findOne({ where: { id } });
  }

  /** Transaction-only row lock used to make finalization idempotent. */
  findByIdForUpdate(id: string, manager: EntityManager): Promise<Match | null> {
    return this.matches(manager)
      .createQueryBuilder('match')
      .setLock('pessimistic_write')
      .where('match.id = :id', { id })
      .getOne();
  }

  /**
   * Find the in-progress match that involves `userId` (either as
   * `player1Id` or `player2Id`). Used by reconnect logic in
   * P0-BE-12 to resume a match after a WS reconnect to a different
   * replica, and by the auth flow to refuse matchmaking when a
   * player already has a live match.
   */
  findActiveByUserId(userId: string): Promise<Match | null> {
    return this.repo
      .createQueryBuilder('m')
      // Keep the player alternatives grouped. Without these parentheses SQL
      // evaluates AND before OR and any historical match where the user was
      // player1 is incorrectly treated as active.
      .where('(m.player1Id = :uid OR m.player2Id = :uid)', { uid: userId })
      .andWhere("m.status = 'in_progress'")
      .getOne();
  }

  async updateState(
    matchId: string,
    side: 'p1' | 'p2',
    state: Record<string, unknown>,
  ): Promise<boolean> {
    const column = side === 'p1' ? 'p1State' : 'p2State';
    const result = await this.repo.update({ id: matchId }, { [column]: state });
    return Boolean(result.affected);
  }

  async updateRuntimeSnapshot(
    matchId: string,
    input: {
      p1State: Record<string, unknown>;
      p2State: Record<string, unknown>;
      wipeIndexP1: number;
      wipeIndexP2: number;
    },
  ): Promise<boolean> {
    const result = await this.repo.update(
      { id: matchId },
      {
        p1State: input.p1State,
        p2State: input.p2State,
        wipeIndexP1: input.wipeIndexP1,
        wipeIndexP2: input.wipeIndexP2,
      },
    );
    return Boolean(result.affected);
  }

  /**
   * Upsert one round while holding the parent Match row lock. The schema has
   * no `(matchId, roundNumber)` unique constraint, so the parent lock keeps
   * retries from creating duplicate replay rows across Nest replicas.
   */
  async saveRoundEvents(
    matchId: string,
    roundNumber: number,
    events: Record<string, unknown>[],
    manager: EntityManager,
  ): Promise<MatchRound> {
    const repo = this.rounds(manager);
    const existing = await repo.findOne({ where: { matchId, roundNumber } });
    if (existing) {
      existing.events = events;
      return repo.save(existing);
    }
    return repo.save(repo.create({ matchId, roundNumber, events }));
  }

  findRounds(matchId: string): Promise<MatchRound[]> {
    return this.roundRepo.find({ where: { matchId }, order: { roundNumber: 'ASC' } });
  }

  findHistoryByUserId(userId: string, limit = 50): Promise<Match[]> {
    return this.repo
      .createQueryBuilder('match')
      .where('(match.player1Id = :userId OR match.player2Id = :userId)', { userId })
      .andWhere("match.status IN ('finished', 'forfeited')")
      .orderBy('match.createdAt', 'DESC')
      .take(Math.min(Math.max(limit, 1), 50))
      .getMany();
  }

  async countRoundsByMatchIds(matchIds: string[]): Promise<Map<string, number>> {
    if (matchIds.length === 0) return new Map();
    const rows = await this.roundRepo
      .createQueryBuilder('round')
      .select('round.matchId', 'matchId')
      .addSelect('COUNT(*)', 'count')
      .where('round.matchId IN (:...matchIds)', { matchIds })
      .groupBy('round.matchId')
      .getRawMany<{ matchId: string; count: string }>();
    return new Map(rows.map((row) => [row.matchId, Number(row.count)]));
  }

  async finalize(
    match: Match,
    input: {
      status: MatchStatus;
      winnerId: string | null;
      finishedAt: Date;
    },
    manager: EntityManager,
  ): Promise<void> {
    await this.matches(manager).update(
      { id: match.id },
      {
        status: input.status,
        winnerId: input.winnerId,
        finishedAt: input.finishedAt,
      },
    );
  }
}
