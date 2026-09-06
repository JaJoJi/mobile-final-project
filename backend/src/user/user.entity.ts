import { Column, CreateDateColumn, Entity, Index, PrimaryGeneratedColumn } from 'typeorm';

/**
 * User account.
 *
 * Schema locked by `docs/02-requirements.md` FR-AUTH-1..4:
 *   - email: valid format, unique
 *   - username: 3–20 chars, alphanumeric + underscore, unique
 *   - passwordHash: bcrypt (≥ 10 rounds), never store plaintext
 *   - rating: starts at 1000, ELO K=32 updated on match end
 *   - createdAt: server time at row insert
 *
 * Note: validation rules for email/username/password are enforced at
 * the DTO layer (class-validator). This entity mirrors only DB shape.
 */
@Entity('users')
@Index('UQ_users_email', ['email'], { unique: true })
@Index('UQ_users_username', ['username'], { unique: true })
export class User {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'varchar', length: 254, unique: true })
  email!: string;

  @Column({ type: 'varchar', length: 20, unique: true })
  username!: string;

  @Column({ type: 'varchar', length: 60 })
  passwordHash!: string;

  @Column({ type: 'int', default: 1000 })
  rating!: number;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;
}
