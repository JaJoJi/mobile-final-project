import { MatchRepository } from './match.repository';

interface ChainState {
  alias: string;
  locks: unknown[];
  wheres: Array<[string, unknown?]>;
  orders: Array<[string, string?]>;
  takes: Array<number | undefined>;
  selects: string[];
  groupBys: string[];
  one: unknown;
  many: unknown;
  raw: unknown;
}

function chainable(state: ChainState): any {
  const qb: any = {
    setLock: (...args: unknown[]) => {
      state.locks.push(args);
      return qb;
    },
    where: (...args: unknown[]) => {
      state.wheres.push(args as [string, unknown?]);
      return qb;
    },
    andWhere: (...args: unknown[]) => {
      state.wheres.push(args as [string, unknown?]);
      return qb;
    },
    orderBy: (...args: unknown[]) => {
      state.orders.push(args as [string, string?]);
      return qb;
    },
    take: (...args: unknown[]) => {
      state.takes.push(args[0] as number | undefined);
      return qb;
    },
    select: (...args: unknown[]) => {
      state.selects.push(args as unknown as string);
      return qb;
    },
    addSelect: (...args: unknown[]) => {
      state.selects.push(args as unknown as string);
      return qb;
    },
    groupBy: (...args: unknown[]) => {
      state.groupBys.push(args as unknown as string);
      return qb;
    },
    getOne: async () => state.one,
    getMany: async () => state.many,
    getRawMany: async () => state.raw,
  };
  return qb;
}

function repoFake() {
  const calls: Record<string, unknown[][]> = {};
  const builders: ChainState[] = [];
  const record =
    (name: string, impl?: (...args: any[]) => Promise<any>) =>
    async (...args: any[]) => {
      (calls[name] ??= []).push(args);
      if (impl) return impl(...args);
      return undefined;
    };
  const repo: any = {
    save: record('save', async (x: unknown) => x),
    create: (x: unknown) => x,
    update: record('update', async () => ({ affected: 1 })),
    findOne: record('findOne', async () => null),
    find: record('find', async () => []),
    findBy: record('findBy', async () => []),
    createQueryBuilder: (alias: string) => {
      (calls.createQueryBuilder ??= []).push([alias]);
      const state: ChainState = {
        alias,
        locks: [],
        wheres: [],
        orders: [],
        takes: [],
        selects: [],
        groupBys: [],
        one: null,
        many: [],
        raw: [],
      };
      builders.push(state);
      return chainable(state);
    },
  };
  return { repo, calls, builders };
}

function harness() {
  const matches = repoFake();
  const rounds = repoFake();
  const repository = new MatchRepository(matches.repo as any, rounds.repo as any);
  const manager = {
    getRepository: (entity: unknown) =>
      (entity as { name?: string }).name === 'MatchRound' ? rounds.repo : matches.repo,
  };
  return { matches, rounds, repository, manager };
}

describe('MatchRepository writes (#309)', () => {
  it('creates with entity defaults when optionals are omitted', async () => {
    const { matches, repository } = harness();
    await repository.create({
      player1Id: 'p1',
      player2Id: 'p2',
      matchSeed: 'seed',
      p1State: {},
      p2State: {},
    });
    expect(matches.calls.save[0][0]).toEqual({
      player1Id: 'p1',
      player2Id: 'p2',
      matchSeed: 'seed',
      p1State: {},
      p2State: {},
    });
  });

  it('forwards explicit status and wipe indexes', async () => {
    const { matches, repository } = harness();
    await repository.create({
      player1Id: 'p1',
      player2Id: 'p2',
      matchSeed: 'seed',
      p1State: {},
      p2State: {},
      status: 'finished',
      wipeIndexP1: 2,
      wipeIndexP2: 3,
    });
    expect(matches.calls.save[0][0]).toMatchObject({
      status: 'finished',
      wipeIndexP1: 2,
      wipeIndexP2: 3,
    });
  });

  it('maps updateState to the correct jsonb column per side', async () => {
    const { matches, repository } = harness();
    await expect(repository.updateState('m1', 'p1', { hp: 1 })).resolves.toBe(true);
    await expect(repository.updateState('m1', 'p2', { hp: 2 })).resolves.toBe(true);
    expect(matches.calls.update).toEqual([
      [{ id: 'm1' }, { p1State: { hp: 1 } }],
      [{ id: 'm1' }, { p2State: { hp: 2 } }],
    ]);
  });

  it('reports false when no snapshot row was affected', async () => {
    const { matches, repository } = harness();
    matches.repo.update = async () => ({ affected: 0 });
    await expect(
      repository.updateRuntimeSnapshot('m1', {
        p1State: {},
        p2State: {},
        wipeIndexP1: 0,
        wipeIndexP2: 0,
      }),
    ).resolves.toBe(false);
  });

  it('upserts round events without duplicating replay rows', async () => {
    const { rounds, repository, manager } = harness();
    const events = [{ type: 'battle_end' }];
    rounds.repo.findOne = async () => ({ id: 'r1', events: [] });
    await repository.saveRoundEvents('m1', 2, events, manager as any);
    expect(rounds.calls.save[0][0]).toMatchObject({ id: 'r1', events });

    rounds.calls.save.length = 0;
    rounds.repo.findOne = async () => null;
    await repository.saveRoundEvents('m1', 3, events, manager as any);
    expect(rounds.calls.save[0][0]).toMatchObject({
      matchId: 'm1',
      roundNumber: 3,
      events,
    });
  });

  it('finalizes through the transactional manager repository', async () => {
    const { matches, repository, manager } = harness();
    const at = new Date();
    await repository.finalize(
      { id: 'm1' } as any,
      { status: 'finished', winnerId: 'p1', finishedAt: at },
      manager as any,
    );
    expect(matches.calls.update[0]).toEqual([
      { id: 'm1' },
      { status: 'finished', winnerId: 'p1', finishedAt: at },
    ]);
  });
});

describe('MatchRepository reads (#309)', () => {
  it('findById queries by primary key and routes through a manager', async () => {
    const { matches, repository, manager } = harness();
    matches.repo.findOne = async (...args: any[]) => {
      (matches.calls.findOne ??= []).push(args);
      return { id: 'm1' };
    };
    await expect(repository.findById('m1')).resolves.toEqual({ id: 'm1' });
    expect(matches.calls.findOne[0]).toEqual([{ where: { id: 'm1' } }]);
    await repository.findById('m1', manager as any);
    expect(matches.calls.findOne).toHaveLength(2);
  });

  it('findByIdForUpdate takes a pessimistic row lock', async () => {
    const { matches: fakes, repository, manager } = harness();
    const builders = fakes.builders;
    await repository.findByIdForUpdate('m1', manager as any);
    const qb = builders[builders.length - 1];
    expect(qb.locks).toEqual([['pessimistic_write']]);
    expect(qb.wheres[0][0]).toBe('match.id = :id');
    expect(qb.wheres[0][1]).toEqual({ id: 'm1' });
  });

  it('findActiveByUserId groups the OR alternatives before the status filter', async () => {
    const { matches: fakes, repository } = harness();
    const builders = fakes.builders;
    await repository.findActiveByUserId('u1');
    const qb = builders[builders.length - 1];
    expect(qb.wheres[0][0]).toBe('(m.player1Id = :uid OR m.player2Id = :uid)');
    expect(qb.wheres[0][1]).toEqual({ uid: 'u1' });
    expect(qb.wheres[1][0]).toBe("m.status = 'in_progress'");
  });

  it('findActiveByUserId reads from PRIMARY (master runner) when a DataSource is present', async () => {
    const { matches: fakes, rounds } = harness();
    const modes: string[] = [];
    const released: string[] = [];
    const dataSource = {
      createQueryRunner: (mode: string) => {
        modes.push(mode);
        return {
          manager: { getRepository: () => fakes.repo },
          release: async () => {
            released.push(mode);
          },
        };
      },
    };
    const repository = new MatchRepository(
      fakes.repo as any,
      rounds.repo as any,
      dataSource as any,
    );
    await repository.findActiveByUserId('u1');
    expect(modes).toEqual(['master']);
    expect(released).toEqual(['master']);
    const qb = fakes.builders[fakes.builders.length - 1];
    expect(qb.wheres[0][0]).toBe('(m.player1Id = :uid OR m.player2Id = :uid)');
  });

  it('findRounds orders replay rows ascending', async () => {
    const { rounds, repository } = harness();
    await repository.findRounds('m1');
    expect(rounds.calls.find[0]).toEqual([
      { where: { matchId: 'm1' }, order: { roundNumber: 'ASC' } },
    ]);
  });

  it('findHistoryByUserId clamps the limit to 1..50 and sorts newest first', async () => {
    const { matches: fakes, repository } = harness();
    const builders = fakes.builders;
    await repository.findHistoryByUserId('u1');
    await repository.findHistoryByUserId('u1', 500);
    await repository.findHistoryByUserId('u1', 0);
    expect(builders.map((b) => b.takes)).toEqual([[50], [50], [1]]);
    const qb = builders[0];
    expect(qb.wheres[0][0]).toBe('(match.player1Id = :userId OR match.player2Id = :userId)');
    expect(qb.wheres[1][0]).toBe("match.status IN ('finished', 'forfeited')");
    expect(qb.orders[0]).toEqual(['match.createdAt', 'DESC']);
  });

  it('countRoundsByMatchIds short-circuits empty input and coerces counts', async () => {
    const { rounds, repository } = harness();
    const out = await repository.countRoundsByMatchIds([]);
    expect(out).toEqual(new Map());
    expect(rounds.calls.createQueryBuilder ?? []).toHaveLength(0);
    rounds.repo.createQueryBuilder = (() => {
      const state: ChainState = {
        alias: 'round',
        locks: [],
        wheres: [],
        orders: [],
        takes: [],
        selects: [],
        groupBys: [],
        one: null,
        many: [],
        raw: [
          { matchId: 'm1', count: '7' },
          { matchId: 'm2', count: '0' },
        ],
      };
      return () => chainable(state);
    })();
    await expect(repository.countRoundsByMatchIds(['m1', 'm2'])).resolves.toEqual(
      new Map([
        ['m1', 7],
        ['m2', 0],
      ]),
    );
  });
});
