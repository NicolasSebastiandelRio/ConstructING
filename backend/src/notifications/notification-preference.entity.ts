import { Column, Entity, PrimaryColumn, UpdateDateColumn } from 'typeorm';

/**
 * CU-71 (Configurar Preferencias de Notificación): canal de correo por
 * usuario. La bandeja in-app es siempre obligatoria; esta preferencia sólo
 * decide si además se envía el aviso por correo.
 *
 * Una fila por usuario (`usuarioId` como clave primaria): si no existe, el
 * servicio la crea con el valor por defecto (`recibirPorCorreo: true`).
 */
@Entity('notification_preferences')
export class NotificationPreferenceEntity {
  @PrimaryColumn()
  usuarioId!: string;

  @Column({ type: 'boolean', default: true })
  recibirPorCorreo!: boolean;

  @UpdateDateColumn()
  updatedAt!: Date;
}
