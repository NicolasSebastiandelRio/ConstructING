import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryColumn,
  UpdateDateColumn,
} from 'typeorm';

/**
 * Réplica en la base maestra de la nube del hito local (CU-44, RF_02).
 *
 * `updatedAt` es la clave del CU-47 (Resolver Conflictos Temporales): la
 * política de última modificación decide cuál versión sobrevive cuando un
 * mismo registro se modificó simultáneamente en dos dispositivos.
 */
@Entity('milestone_sync')
@Index('idx_milestone_sync_obra', ['obraId'])
export class MilestoneSyncEntity {
  @PrimaryColumn('uuid')
  id!: string;

  @Column('uuid')
  obraId!: string;

  @Column()
  nombre!: string;

  @Column({ type: 'text', nullable: true })
  descripcion!: string | null;

  @Column('int')
  duracionDias!: number;

  @Column()
  estado!: string;

  @Column('boolean', { default: false })
  esCritico!: boolean;

  /**
   * Reloj de la última modificación local (CU-47). Opcional SIN unión
   * `| null`: con unión TypeORM refleja el tipo como `Object` y Postgres
   * lo rechaza; así infiere `timestamp`/`datetime` según el motor (mismo
   * patrón que `WorkInvitationEntity.usedAt`). En BD/JSON el pendiente es
   * NULL.
   */
  @Column({ nullable: true })
  updatedAtLocal?: Date;

  @CreateDateColumn()
  createdAt!: Date;

  @UpdateDateColumn()
  updatedAt!: Date;
}
