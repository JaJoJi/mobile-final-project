/** Combat-engine test config (P3-BE-01). */
/** @type {import('jest').Config} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src'],
  testRegex: '.*\\.spec\\.ts$',
  collectCoverageFrom: [
    'src/game/**/*.ts',
    '!src/game/**/*.spec.ts',
    '!src/game/**/*.smoke.ts',
    '!src/game/fixtures/**',
    '!src/game/index.ts',
  ],
  coverageDirectory: 'coverage',
  // NFR-9: the combat engine must stay at ≥ 90 % line coverage.
  coverageThreshold: {
    global: { lines: 90, statements: 90, functions: 90, branches: 80 },
  },
};
