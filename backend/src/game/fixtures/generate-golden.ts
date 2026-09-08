/**
 * Regenerates `golden-battle.json` — the byte-for-byte reference output
 * of a fixed 9v9 battle. Run only when combat behaviour changes on purpose:
 *
 *   npx ts-node -T src/game/fixtures/generate-golden.ts
 *
 * The board here MUST match `engine.spec.ts`'s `build()`.
 */
import { writeFileSync } from 'fs';
import { join } from 'path';
import { runBattle } from '../engine';
import type { UnitInstance } from '../types';
import { makeBattleState, makeUnit, resetIds } from './board-builder';

resetIds();
const kinds = [
  'fighter', 'ranger', 'healer', 'tank', 'fighter', 'ranger', 'healer', 'tank', 'fighter',
] as const;

const side = (s: 'p1' | 'p2'): UnitInstance[] =>
  kinds.map((k, i) =>
    makeUnit({
      unitId: k,
      star: (i % 3) as 0 | 1 | 2,
      slot: i,
      side: s,
      hp: 60 + i * 10,
      maxHp: 60 + i * 10,
    }),
  );

const events = runBattle(
  makeBattleState({ p1Units: side('p1'), p2Units: side('p2'), roundSeed: 777 }),
);

const out = join(__dirname, 'golden-battle.json');
writeFileSync(out, `${JSON.stringify(events, null, 2)}\n`);
console.log(`wrote ${events.length} events → ${out}`);
