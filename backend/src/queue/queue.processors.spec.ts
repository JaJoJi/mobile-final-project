jest.mock('@nestjs/bullmq', () => ({
  Processor: () => () => undefined,
  WorkerHost: class WorkerHost {},
  InjectQueue: () => () => undefined,
}));

import { JOB_NAMES } from './queue.constants';
import {
  CombatDoneTimeoutProcessor,
  DisconnectDetectProcessor,
  PhaseTimerProcessor,
} from './queue.processors';

const roundJob = (name: string, matchId = 'match-1', round = 2) =>
  ({ name, data: { matchId, round } }) as any;

describe('PhaseTimerProcessor (#307)', () => {
  it('ignores unknown job names without touching the runtime', async () => {
    const runtime = { tryStartCombat: jest.fn() };
    const processor = new PhaseTimerProcessor(runtime as any);
    await processor.process({ name: 'something-else', data: {} } as any);
    expect(runtime.tryStartCombat).not.toHaveBeenCalled();
  });

  it('delegates phase starts and passes the started flag through', async () => {
    const runtime = { tryStartCombat: jest.fn(async () => true) };
    const processor = new PhaseTimerProcessor(runtime as any);
    await processor.process(roundJob(JOB_NAMES.PHASE_START));
    expect(runtime.tryStartCombat).toHaveBeenCalledWith('match-1', 2);
  });

  it('a stale timer for an already-advanced round is a safe no-op', async () => {
    // tryStartCombat returns false when phase/round moved on (CAS loser);
    // the processor must not retry or throw.
    const runtime = { tryStartCombat: jest.fn(async () => false) };
    const processor = new PhaseTimerProcessor(runtime as any);
    await expect(
      processor.process(roundJob(JOB_NAMES.PHASE_START, 'match-1', 1)),
    ).resolves.toBeUndefined();
    expect(runtime.tryStartCombat).toHaveBeenCalledWith('match-1', 1);
  });
});

describe('CombatDoneTimeoutProcessor (#307)', () => {
  it('ignores unknown job names', async () => {
    const runtime = { applyDamageAndAdvance: jest.fn() };
    const processor = new CombatDoneTimeoutProcessor(runtime as any);
    await processor.process({ name: 'nope', data: {} } as any);
    expect(runtime.applyDamageAndAdvance).not.toHaveBeenCalled();
  });

  it('fires the shared advance path so late timeouts converge safely', async () => {
    const runtime = { applyDamageAndAdvance: jest.fn(async () => true) };
    const processor = new CombatDoneTimeoutProcessor(runtime as any);
    await processor.process(roundJob(JOB_NAMES.COMBAT_DONE_TIMEOUT));
    expect(runtime.applyDamageAndAdvance).toHaveBeenCalledWith('match-1', 2);
  });

  it('a timeout arriving after both acks already advanced is a no-op', async () => {
    const runtime = { applyDamageAndAdvance: jest.fn(async () => false) };
    const processor = new CombatDoneTimeoutProcessor(runtime as any);
    await expect(
      processor.process(roundJob(JOB_NAMES.COMBAT_DONE_TIMEOUT)),
    ).resolves.toBeUndefined();
  });
});

describe('DisconnectDetectProcessor (#307)', () => {
  it('ignores unknown job names', async () => {
    const runtime = { handleDisconnect: jest.fn() };
    const processor = new DisconnectDetectProcessor(runtime as any);
    await processor.process({ name: 'nope', data: {} } as any);
    expect(runtime.handleDisconnect).not.toHaveBeenCalled();
  });

  it('forwards the explicit match+user form so stale jobs cannot hit newer matches', async () => {
    const runtime = { handleDisconnect: jest.fn(async () => true) };
    const processor = new DisconnectDetectProcessor(runtime as any);
    await processor.process({
      name: JOB_NAMES.DISCONNECT_DETECT,
      data: { matchId: 'match-1', userId: 'player-1' },
    } as any);
    expect(runtime.handleDisconnect).toHaveBeenCalledWith('match-1', 'player-1');
  });
});
