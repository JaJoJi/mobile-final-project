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

  coverageDirectory: '<rootDir>/coverage',

  coverageReporters: [
    'text',
    'lcov',
    'cobertura',
  ],

  reporters: [
    'default',
    [
      'jest-junit',
      {
        outputDirectory: 'reports',
        outputName: 'junit.xml',
      },
    ],
  ],
};