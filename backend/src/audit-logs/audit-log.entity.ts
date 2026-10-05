import { Column, CreateDateColumn, Entity, Index, PrimaryColumn } from 'typeorm';

/**
 * CU-60 (RF_08, RNF_S_03): registro inmutable de auditoría.
 *
 * Guarda de forma transparente qué actor hizo qué acción, a qué hora y
 * dónde. El timestamp es el emitido por el servidor (paso 2). RNF_S_03:
 * estricta prohibición a nivel de BD de ejecutar UPDATE o DELETE sobre
 * esta tabla — el servicio solo expone INSERT/SELECT y en Supabase la
 * tabla debe declararse sin permisos de escritura post-insert (RLS).
 */
@Entity('audit_logs')
@Index('idx_audit_logs_obra', ['obraId'])
export class AuditLogEntity {
  @PrimaryColumn('uuid')
  id!: string;

  @Column()
  usuarioId!: string;

  /** Tipo de acción crítica (hito_modificado, evidencia_cargada, acta_sellada…). */
  @Column()
  accion!: string;

  @Column({ type: 'text', nullable: true })
  detalle!: string | null;

  @Column({ type: 'text', nullable: true })
  obraId!: string | null;

  /** Coordenadas actuales informadas por el módulo de origen. */
  @Column({ type: 'text', nullable: true })
  coordenadas!: string | null;

  @CreateDateColumn()
  createdAt!: Date;
}
