import { Injectable, Logger, NotFoundException, Optional } from '@nestjs/common';
import { InjectDataSource, InjectRepository } from '@nestjs/typeorm';
import { DataSource, EntityManager, In, Repository } from 'typeorm';
import { runOnMaster } from '../database/postgres-replication';
import { User } from './user.entity';

/**
 * User domain operations.
 *
 * Single place that talks to the `users` repository — keeps query
 * logic out of controllers and out of AuthService. AuthService uses
 * this for register/login/refresh; UserController uses it for /user/me.
 *
 * Read routing with PG read/write splitting:
 *   - `findById` / `findByEmail` / `findByUsername` ALWAYS read from the
 *     PRIMARY. These are tiny PK/unique lookups on the auth path
 *     (register → login, token refresh, `/user/me`), where a stale
 *     replica read right after registration would wrongly 401/404.
 *   - `findByIds` (plural, used for opponent/username resolution) uses the
 *     default routing (replica when configured); callers that need strong
 *     consistency pass a master `EntityManager` instead.
 */
@Injectable()
export class UserService {
  private readonly logger = new Logger(UserService.name);

  constructor(
    @InjectRepository(User) private readonly users: Repository<User>,
    // Optional so unit/smoke fakes (`new UserService(repo)`) keep working.
    @Optional() @InjectDataSource()
    private readonly dataSource?: DataSource,
  ) {}

  private repository(manager?: EntityManager): Repository<User> {
    return manager?.getRepository(User) ?? this.users;
  }

  /** PRIMARY read (see class comment). Honors an explicit tx manager. */
  findById(id: string, manager?: EntityManager): Promise<User | null> {
    if (manager) return manager.getRepository(User).findOne({ where: { id } });
    if (this.dataSource) {
      return runOnMaster(this.dataSource, (m) =>
        m.getRepository(User).findOne({ where: { id } }),
      );
    }
    return this.users.findOne({ where: { id } });
  }

  findByIds(ids: string[], manager?: EntityManager): Promise<User[]> {
    if (ids.length === 0) return Promise.resolve([]);
    return this.repository(manager).findBy({ id: In(ids) });
  }

  findByIdsForUpdate(ids: string[], manager: EntityManager): Promise<User[]> {
    if (ids.length === 0) return Promise.resolve([]);
    return this.repository(manager)
      .createQueryBuilder('user')
      .setLock('pessimistic_write')
      .where('user.id IN (:...ids)', { ids: [...ids].sort() })
      .orderBy('user.id', 'ASC')
      .getMany();
  }

  /** PRIMARY read: login must observe just-registered users (no WAL lag). */
  findByEmail(email: string, manager?: EntityManager): Promise<User | null> {
    const where = { email: email.toLowerCase() };
    if (manager) return manager.getRepository(User).findOne({ where });
    if (this.dataSource) {
      return runOnMaster(this.dataSource, (m) =>
        m.getRepository(User).findOne({ where }),
      );
    }
    return this.users.findOne({ where });
  }

  /** PRIMARY read: same staleness reasoning as `findByEmail`. */
  findByUsername(username: string, manager?: EntityManager): Promise<User | null> {
    if (manager) return manager.getRepository(User).findOne({ where: { username } });
    if (this.dataSource) {
      return runOnMaster(this.dataSource, (m) =>
        m.getRepository(User).findOne({ where: { username } }),
      );
    }
    return this.users.findOne({ where: { username } });
  }

  /**
   * Insert a new user row. Caller is responsible for bcrypt-hashing
   * the password before passing it in.
   *
   * Throws ConflictException indirectly via PG 23505; AuthService
   * translates the raw error to a 409 with a precise field code.
   */
  create(input: { email: string; username: string; passwordHash: string }): Promise<User> {
    return this.users.save(
      this.users.create({
        email: input.email.toLowerCase(),
        username: input.username,
        passwordHash: input.passwordHash,
      }),
    );
  }

  /**
   * Update the username. Returns the updated row. Throws NotFound
   * if no user matches the id.
   */
  async updateUsername(id: string, username: string): Promise<User> {
    const result = await this.users.update({ id }, { username });
    if (!result.affected) {
      throw new NotFoundException(`user ${id} not found`);
    }
    const fresh = await this.findById(id);
    if (!fresh) {
      // Should not happen — we just updated a row that existed.
      throw new NotFoundException(`user ${id} not found after update`);
    }
    return fresh;
  }

  /** Apply an ELO delta atomically and clamp the persisted rating at zero. */
  async updateRating(id: string, delta: number, manager?: EntityManager): Promise<void> {
    const result = await this.repository(manager)
      .createQueryBuilder()
      .update(User)
      .set({ rating: () => 'GREATEST(0, "rating" + :delta)' })
      .where('id = :id', { id })
      .setParameters({ delta: Math.trunc(delta) })
      .execute();
    if (!result.affected) throw new NotFoundException(`user ${id} not found`);
  }
}
