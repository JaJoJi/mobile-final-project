import { User } from '../user/user.entity';
// import { Match } from '../match/match.entity';                  // added by P0-BE-07
// import { MatchRound } from '../match/match-round.entity';       // added by P0-BE-07

/**
 * Single source of truth for TypeORM entity registration.
 *
 * Why: every persistent entity flows through this list. Avoids the
 * "I added an entity but forgot to register it in TypeOrmModule" bug.
 *
 * To add a new entity:
 *   1. Create `backend/src/<feature>/<name>.entity.ts` with `@Entity()`.
 *   2. Import + add it here.
 *   3. Run `npm run migration:generate -- src/migrations/<PascalCaseName>`.
 *   4. Review the generated SQL, then commit.
 *
 * nest-1 runs migrations on boot (RUN_MIGRATIONS=true); nest-2/3 skip.
 */
export const ENTITIES = [User];
