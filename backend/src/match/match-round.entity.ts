import { Column, CreateDateColumn, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

/**
 * Per-round combat event log for a match.
 *
 * Schema mirrors `docs/03-architecture.md §3.3`. `events` is the full
 * `CombatEvent[]` array returned by the engine (P0-BE-09) for one round —
 * typically 100–2000 events. This is the source of truth for replay
 * (race R20 in §14): if a snapshot write fails the match still ended
 * correctly; the event log here is what `game:combat:events` consumers
 * use to reconstruct what happened.
 *
 * `matchId` is a plain uuid column (not a TypeORM `@ManyToOne`) so the
 * entity is cheap to insert from hot-path code in the orchestrator —
 * no eager / lazy loading. The `CreateMatches` migration adds the FK
 * `matchId REFERENCES matches(id) ON DELETE CASCADE` by hand, so the
 * schema is still enforcing referential integrity.
 */
@Entity('match_rounds')
@Index('IDX_match_rounds_matchId', ['matchId'])
export class MatchRound {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column('uuid')
  matchId!: string;

  @Column('int')
  roundNumber!: number;

  /** Full ordered `CombatEvent[]` for this round (see `docs/04-api-contracts.md §2.1`). */
  @Column({ type: 'jsonb' })
  events!: Record<string, unknown>[];

  @CreateDateColumn({ type: 'timestamptz', default: () => 'now()' })
  createdAt!: Date;
}
