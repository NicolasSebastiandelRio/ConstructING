import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryColumn,
  UpdateDateColumn,
} from 'typeorm';

/**
 * Réplica en la base maestra de la nube de la evidencia pericial
 * (CU-44, RF_03/RF_04). El binario se almacena en disco bajo
 * `UPLOAD_DIR` y el `checksum` SHA-256 respalda el CU-45 (RNF_C_03).
 */
@Entity('evidence_sync')
@Index('idx_evidence_sync_hito', ['hitoId'])
@Index('idx_evidence_sync_obra', ['obraId'])
export class EvidenceSyncEntity {
  @PrimaryColumn('uuid')
  id!: string;

  @Column('uuid')
  hitoId!: string;

  @Column('uuid')
  obraId!: string;

  /** 'Foto' | 'Video' (CU-32 / CU-33). */
  @Column()
  tipo!: string;

  @Column({ type: 'text', nullable: true })
  nota!: string | null;

  @Column('double precision')
  latitud!: number;

  @Column('double precision')
  longitud!: number;

  @Column('double precision')
  precisionM!: number;

  @Column({ type: 'timestamptz' })
  fechaCaptura!: Date;

  @Column('double precision', { nullable: true })
  duracionSeg!: number | null;

  @Column('int')
  tamanoBytes!: number;

  /** SHA-256 del archivo original (CU-45). */
  @Column()
  checksum!: string;

  /** Marca pericial persistida (CU-36, RNF_S_04). */
  @Column({ type: 'text' })
  marcaTexto!: string;

  /** Nombre del archivo almacenado en el directorio de la nube. */
  @Column()
  archivoNombre!: string;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt!: Date;
}
