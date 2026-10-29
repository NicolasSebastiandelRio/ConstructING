import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryColumn,
} from 'typeorm';

/**
 * CU-70 (Consultar Notificaciones) / CU-72 (Badge de pendientes): bandeja
 * in-app de notificaciones del usuario.
 *
 * Cada fila es un aviso dirigido a un destinatario (`usuarioId`). El `id` lo
 * genera el cliente que dispara el evento (o el cron) para poder sincronizar
 * de forma idempotente, por eso es `PrimaryColumn` y no `@PrimaryGeneratedColumn`.
 */
@Entity('notifications')
@Index('idx_notifications_usuario', ['usuarioId'])
export class NotificationEntity {
  @PrimaryColumn('uuid')
  id!: string;

  /** Destinatario del aviso. */
  @Column()
  usuarioId!: string;

  /** 'avance' | 'firma' | 'retraso' (CU-67..CU-69). */
  @Column()
  tipo!: string;

  @Column()
  titulo!: string;

  @Column({ type: 'text' })
  mensaje!: string;

  @Column({ type: 'text', nullable: true })
  obraId!: string | null;

  @Column({ type: 'text', nullable: true })
  hitoId!: string | null;

  /** 'alta' | 'normal'. */
  @Column({ default: 'normal' })
  prioridad!: string;

  /** CU-72: `true` cuando el usuario abrió/leyó el aviso. */
  @Column({ type: 'boolean', default: false })
  leida!: boolean;

  @CreateDateColumn()
  createdAt!: Date;
}
