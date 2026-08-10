import { Entity, Column, PrimaryGeneratedColumn, CreateDateColumn } from 'typeorm';

@Entity('usuarios') 
export class UserEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true, length: 150 })
  email: string;

  @Column({ name: 'password_hash' })
  passwordHash: string;

  @Column({ length: 50 })
  role: string; 

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

@Column({ name: 'recovery_code', type: 'varchar', nullable: true })
  recoveryCode: string | null;
}