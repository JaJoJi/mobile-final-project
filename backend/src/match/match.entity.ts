import { Column, CreateDateColumn, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

export type MatchStatus = 'in_progress' | 'finished' | 'forfeited';

/**
 * Persistent snapshot of a match.
 *
 * Schema mirrors `docs/03-architecture.md §3.2` with two extra columns from
 * the issue spec: `matchSeed` (UUID, unique — feeds deterministic replay
 * and is what `combat-lock:<id>` references as the "round RNG key") and
 * `wipeIndexP1/P2` (current wipe count driving damage in `docs/01 §6`).
 *
 * Mutable game state lives in Redis (`match:<id>:runtime` HASH per §4.1).
 * The `p1State` / `p2State` jsonb columns are **periodic snapshots** —
 * last-write-wins at the row level (race R19 in §14) — used for replay
 * and for the `/match/history` endpoint (P0-FE-02). They are not the
 * source of truth for in-flight match state; the source of truth is
 * Redis + the per-round `match_rounds.events` log (race R20).
 *
 * `finishedAt` is a plain nullable timestamp (NOT `@UpdateDateColumn`,
 * which would auto-bump on every repository save). The P0-BE-12 match
 * lifecycle service is the only thing that ever sets it — when
 * `status` flips to `finished` / `forfeited`.
 */
@Entity('matches')
@Index('UQ_matches_seed', ['matchSeed'], { unique: true })
export class Match {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column('uuid')
  player1Id!: string;

  @Column('uuid')
  player2Id!: string;

  @Column({ type: 'uuid', nullable: true })
  winnerId!: string | null;

  @Column({ type: 'varchar', length: 16, default: 'in_progress' })
  status!: MatchStatus;

  @Column('uuid')
  matchSeed!: string;

  @Column({ type: 'int', default: 0 })
  wipeIndexP1!: number;

  @Column({ type: 'int', default: 0 })
  wipeIndexP2!: number;

  /** Per-player snapshot — HP / gold / roster / ready. Shape is open; validated at DTO / service layer. */
  @Column({ type: 'jsonb' })
  p1State!: Record<string, unknown>;

  @Column({ type: 'jsonb' })
  p2State!: Record<string, unknown>;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @Column({ type: 'timestamptz', nullable: true })
  finishedAt!: Date | null;
}
