import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { EntityManager, In, Repository } from 'typeorm';
import { User } from './user.entity';

/**
 * User domain operations.
 *
 * Single place that talks to the `users` repository — keeps query
 * logic out of controllers and out of AuthService. AuthService uses
 * this for register/login/refresh; UserController uses it for /user/me.
 */
@Injectable()
export class UserService {
  private readonly logger = new Logger(UserService.name);

  constructor(@InjectRepository(User) private readonly users: Repository<User>) {}

  private repository(manager?: EntityManager): Repository<User> {
    return manager?.getRepository(User) ?? this.users;
  }

  findById(id: string, manager?: EntityManager): Promise<User | null> {
    return this.repository(manager).findOne({ where: { id } });
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

  findByEmail(email: string): Promise<User | null> {
    return this.users.findOne({ where: { email: email.toLowerCase() } });
  }

  findByUsername(username: string): Promise<User | null> {
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
