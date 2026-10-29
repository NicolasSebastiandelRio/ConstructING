import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
} from 'typeorm';
import { WorkEntity } from './work.entity';

/**
 * CU-22: Invitación para que un propietario no registrado se una a su obra.
 * El código es único y temporal (expira); al registrarse con él (CU-06), el
 * nuevo usuario queda vinculado como propietario de la obra (reclamo).
 */
@Entity('work_invitations')
export class WorkInvitationEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  /** Código único legible para compartir (ej. CNG-7K2P9Q). */
  @Column({ unique: true, length: 16 })
  code!: string;

  @Column()
  workId!: string;

  @ManyToOne(() => WorkEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'workId' })
  work!: WorkEntity;

  /** Correo del propietario invitado (normalizado a minúsculas). */
  @Column({ length: 150 })
  email!: string;

  /**
   * Vencimiento temporal del código (CU-22: "código único temporal"). Sin
   * `type` explícito: TypeORM infiere `timestamp` en PostgreSQL y `datetime`
   * en SQLite (`datetime` literal NO es válido en Postgres).
   */
  @Column()
  expiresAt!: Date;

  /**
   * Reclamo: fecha en que el código fue usado en un registro (ausente =
   * pendiente). Se declara opcional SIN unión `| null`: con unión, TypeORM
   * refleja el tipo como `Object` y Postgres lo rechaza; así infiere
   * `timestamp`/`datetime` según el motor. En BD/JSON el pendiente es NULL.
   */
  @Column({ nullable: true })
  usedAt?: Date;

  @CreateDateColumn()
  createdAt!: Date;
}