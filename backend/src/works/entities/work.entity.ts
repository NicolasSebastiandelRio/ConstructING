import { 
  Entity, 
  PrimaryGeneratedColumn, 
  Column, 
  ManyToOne, 
  JoinColumn, 
  CreateDateColumn, 
  UpdateDateColumn, 
  DeleteDateColumn 
} from 'typeorm';
import { UserEntity } from '../../auth/user.entity';

export enum WorkStatus {
  PLANIFICATION = 'En Planificación',
  IN_PROGRESS = 'En Ejecución',
  COMPLETED = 'Completado',
  ARCHIVED = 'Archivado',
}

@Entity('works')
export class WorkEntity {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'varchar', length: 150 })
  nombre!: string;

  @Column({ type: 'text' })
  direccion!: string;

  @Column({ type: 'date' })
  fechaInicio!: string;

  /**
   * CU-30: fecha final estimada del proyecto, ajustada automáticamente por
   * la ruta crítica (duración total en días desde fechaInicio). Nula hasta
   * el primer recálculo.
   */
  @Column({ name: 'fecha_fin_estimada', type: 'date', nullable: true })
  fechaFinEstimada?: string | null;

  @Column({ type: 'text', nullable: true })
  descripcion?: string; // Opcional (permite valores nulos)

  @Column({ type: 'float', nullable: true })
  latitud?: number;

  @Column({ type: 'float', nullable: true })
  longitud?: number;

  @Column({ 
    type: 'simple-enum', // Clave para compatibilidad polimórfica: PostgreSQL y SQLite (better-sqlite3)
    enum: WorkStatus, 
    default: WorkStatus.PLANIFICATION 
  })
  estado!: WorkStatus;

  // Relación N:1 con Usuario (Propietario) - Garantiza RNF-D-03 (Integridad Relacional)
  @ManyToOne(() => UserEntity, { eager: true, onDelete: 'RESTRICT' })
  @JoinColumn({ name: 'propietarioId' })
  propietario!: UserEntity;

  @Column()
  propietarioId!: string;

  @CreateDateColumn()
  createdAt!: Date;

  @UpdateDateColumn()
  updatedAt!: Date;

  @DeleteDateColumn()
  deletedAt?: Date; // Soporte para RNF-S-03 (Soft-Delete / Audit Log)
}