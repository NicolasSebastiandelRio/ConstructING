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

  /** Reloj de la última modificación local (CU-47). */
  @Column({ type: 'timestamptz', nullable: true })
  updatedAtLocal!: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt!: Date;
}
