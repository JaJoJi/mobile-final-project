/** Combat-engine test config (P3-BE-01). */
/** @type {import('jest').Config} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testRegex: '.*\\.spec\\.ts$',
  collectCoverageFrom: [
    'src/**/*.ts',
    '!src/**/*.spec.ts',
    '!src/**/*.smoke.ts',
    '!src/**/*.integration.smoke.ts',
    '!src/**/fixtures/**',
    '!src/game/index.ts',
    '!src/main.ts',
    '!src/data-source.ts',
    '!src/migrations/**',
    '!src/**/*.module.ts',
    '!src/**/*.dto.ts',
    '!src/**/*.entity.ts',
  ],
  coverageDirectory: 'coverage',
  coverageThreshold: {
    // NFR-9: the combat engine must stay at ≥ 90 % line coverage. This
    // glob is checked per-file (jest semantics), and every file under
    // src/game/ individually clears it today.
    'src/game/**/*.ts': { lines: 90, statements: 90, functions: 90, branches: 80 },
    // Floor (not a target) for everything outside src/game/ — jest
    // excludes glob-matched files from `global` once any glob is
    // present, so this is the real rest-of-backend average
    // (auth/matchmaking/shop/ws/common/runtime/redis/queue/match/user/
    // database), pinned just under the measured baseline as of
    // 2026-09-24 (43.55/37.52/44.59/44.91 — see #273) so a PR can't
    // silently regress it back toward zero. A per-directory floor
    // doesn't work here — jest checks glob thresholds per file, and
    // most non-game files sit at 0% today (no tests written yet), so
    // any per-directory floor above 0% fails immediately on those.
    // Raise these numbers as coverage actually improves.
    global: { statements: 43, branches: 37, functions: 44, lines: 44 },
  },
};
