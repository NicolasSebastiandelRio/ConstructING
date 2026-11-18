import { Column, CreateDateColumn, Entity, Index, PrimaryColumn } from 'typeorm';

/**
 * CU-59 (RF_08, RNF_C_05): certificación sellada del acta de conformidad.
 * Cada fila guarda el identificador criptográfico inmutable (hash SHA-256)
 * del documento PDF consolidado y finalizado: el documento legal queda
 * sellado lógicamente contra modificaciones post-firma.
 */
@Entity('certifications')
@Index('idx_certifications_hito', ['hitoId'])
export class CertificationEntity {
  /** Identificador del acta asignado por el dispositivo al compilarla. */
  @PrimaryColumn('uuid')
  id!: string;

  @Column('uuid')
  hitoId!: string;

  @Column('uuid')
  obraId!: string;

  /** Sello SHA-256 (hex) de la totalidad del documento binario. */
  @Column()
  hashSha256!: string;

  /** Nombre del archivo del acta (convención acta_<hitoId>.pdf). */
  @Column()
  archivoNombre!: string;

  /** Rol del firmante de la conformidad (Profesional/Propietario). */
  @Column({ type: 'text', nullable: true })
  firmante!: string | null;

  @CreateDateColumn()
  createdAt!: Date;
}
