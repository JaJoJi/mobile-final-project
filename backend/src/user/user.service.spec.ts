import { UserService } from './user.service';

function chain(result: { affected?: number | null } | unknown[] = { affected: 1 }) {
  const self: any = {
    calls: [] as string[],
    updateValue: null as unknown,
    updateWhere: null as unknown,
    setParametersValue: null as unknown,
  };
  self.update = (...args: unknown[]) => {
    self.calls.push('update');
    self.updateValue = args;
    return self;
  };
  self.set = (...args: unknown[]) => {
    self.calls.push('set');
    self.updateValue = args;
    return self;
  };
  self.where = (...args: unknown[]) => {
    self.calls.push('where');
    self.updateWhere = args;
    return self;
  };
  self.setParameters = (...args: unknown[]) => {
    self.setParametersValue = args;
    return self;
  };
  self.setLock = () => self;
  self.orderBy = () => self;
  self.execute = async () => result;
  self.getMany = async () => result;
  return self;
}

const makeService = (overrides: Record<string, (...args: any[]) => Promise<any>> = {}) => {
  const calls: Record<string, unknown[][]> = {};
  const record = (name: string) => async (...args: any[]) => {
    (calls[name] ??= []).push(args);
    if (overrides[name]) return overrides[name](...args);
    return undefined;
  };
  const qb = chain();
  const repo = {
    findOne: record('findOne'),
    findBy: record('findBy'),
    create: (input: unknown) => input,
    save: record('save'),
    update: record('update'),
    createQueryBuilder: (...args: unknown[]) => {
      (calls.createQueryBuilder ??= []).push(args);
      return qb;
    },
    getRepository: () => repo,
  };
  const service = new UserService(repo as any);
  return { repo, qb, calls, service };
};

describe('UserService reads (#308)', () => {
  it('findByIds short-circuits empty input without touching the repository', async () => {
    const { calls, service } = makeService({
      findBy: async () => {
        throw new Error('should not be called');
      },
    });
    await expect(service.findByIds([])).resolves.toEqual([]);
    expect(calls.findBy ?? []).toHaveLength(0);
  });

  it('lowercases email lookups and creations for case-insensitive identity', async () => {
    const { calls, service } = makeService({
      findOne: async () => null,
      save: async (input: any) => ({ id: 'u1', ...input }),
    });
    await service.findByEmail('ALICE@Example.COM');
    expect(calls.findOne[0][0]).toEqual({ where: { email: 'alice@example.com' } });
    const created = await service.create({
      email: 'BOB@Example.COM',
      username: 'bob',
      passwordHash: 'h',
    });
    expect(created.email).toBe('bob@example.com');
  });

  it('locks user rows in sorted id order to avoid deadlock on finalize', async () => {
    const { qb, service } = makeService();
    qb.getMany = async () => [];
    const manager = { getRepository: () => ({ createQueryBuilder: () => qb }) };
    await service.findByIdsForUpdate(['user-b', 'user-a'], manager as any);
    const where = qb.updateWhere as [string, Record<string, unknown>];
    expect(where[0]).toContain('IN (:...ids)');
    expect(where[1]).toEqual({ ids: ['user-a', 'user-b'] });
    await expect(service.findByIdsForUpdate([], manager as any)).resolves.toEqual([]);
  });
});

describe('UserService mutations (#308)', () => {
  it('updateUsername returns the fresh row and 404s unknown users', async () => {
    const { service } = makeService({
      update: async () => ({ affected: 1 }),
      findOne: async () => ({ id: 'u1', username: 'new' }),
    });
    await expect(service.updateUsername('u1', 'new')).resolves.toMatchObject({
      username: 'new',
    });

    const missing = makeService({ update: async () => ({ affected: 0 }) });
    await expect(missing.service.updateUsername('ghost', 'x')).rejects.toMatchObject({
      status: 404,
    });
  });

  it('updateRating clamps at zero with a truncated delta and 404s unknown users', async () => {
    const { qb, service } = makeService();
    await service.updateRating('u1', 16.9);
    expect(qb.setParametersValue).toEqual([{ delta: 16 }]);
    const setArg = (qb.updateValue as [Record<string, () => string>])[0];
    expect(typeof setArg.rating).toBe('function');

    const failing = makeService();
    (failing.qb as any).execute = async () => ({ affected: 0 });
    await expect(failing.service.updateRating('ghost', 1)).rejects.toMatchObject({
      status: 404,
    });
  });
});
