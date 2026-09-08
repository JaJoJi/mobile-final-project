import type { runBattle } from '../game';

export const RUN_BATTLE = Symbol('RUN_BATTLE');
export type RunBattle = typeof runBattle;
