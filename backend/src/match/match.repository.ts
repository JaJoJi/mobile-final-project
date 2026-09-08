import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Match, MatchStatus } from './match.entity';

/**
 * Data access for the `matches` table.
 *
 * Thin wrapper over `Repository<Match>` — keeps query logic out of the
 * service / orchestrator layers (P0-BE-12, P0-BE-13) so DB shapes
 * never leak past this seam. Namesake follows the issue spec for
 * P0-BE-07 (diverges from the `UserService` naming but is intentional
 * — the orchestrator owns match lifecycle, this layer is just IO).
 *
 * Lifecycle methods that mutate `status` / `finishedAt` / `wipeIndex*`
 * live in P0-BE-12's `MatchService` and call into this repo. The repo
 * stays read-mostly + the simple create, leaving the orchestrator
 * free to compose `EntityManager` transactions for atomic multi-row
 * updates without going through a third abstraction.
 */
@Injectable()
export class MatchRepository {
  constructor(
    @InjectRepository(Match)
    private readonly repo: Repository<Match>,
  ) {}

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
  findById(id: string): Promise<Match | null> {
    return this.repo.findOne({ where: { id } });
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
      .where('m.player1Id = :uid OR m.player2Id = :uid', { uid: userId })
      .andWhere("m.status = 'in_progress'")
      .getOne();
  }
}
