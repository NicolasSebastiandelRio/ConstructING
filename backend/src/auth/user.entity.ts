import { Entity, Column, PrimaryGeneratedColumn, CreateDateColumn, DeleteDateColumn } from 'typeorm';

@Entity('usuarios') 
export class UserEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'nombre_completo', length: 100, default: '' })
  nombre: string;

  @Column({ unique: true, length: 150 })
  email: string;

  @Column({ name: 'password_hash' })
  passwordHash: string;

  @Column({ length: 50 })
  role: string; 

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  /**
   * CU-08 (RNF_S_03): marca de borrado lógico. Al estar poblada, el usuario
   * queda "Inactivo": TypeORM lo excluye de las consultas normales (login),
   * pero sus registros históricos y relaciones se conservan intactos.
   */
  @DeleteDateColumn({ name: 'deleted_at', nullable: true })
  deletedAt: Date | null;

@Column({ name: 'recovery_code', type: 'varchar', nullable: true })
  recoveryCode: string | null;
}