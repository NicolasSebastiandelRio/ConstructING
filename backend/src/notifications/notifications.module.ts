import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { NotificationEntity } from './notification.entity';
import { NotificationPreferenceEntity } from './notification-preference.entity';
import { NotificationsService } from './notifications.service';
import { NotificationsScheduler } from './notifications.scheduler';
import { NotificationsController } from './notifications.controller';
import { WorkEntity } from '../works/entities/work.entity';

/**
 * Módulo de notificaciones del Sprint 6 (CU-67..CU-72, PT-08).
 *
 * `WorkEntity` se registra para que el chequeo de retrasos (CU-69) pueda
 * consultar las obras En Ejecución con fecha de fin estimada vencida.
 */
@Module({
  imports: [
    TypeOrmModule.forFeature([
      NotificationEntity,
      NotificationPreferenceEntity,
      WorkEntity,
    ]),
  ],
  controllers: [NotificationsController],
  providers: [NotificationsService, NotificationsScheduler],
  exports: [NotificationsService],
})
export class NotificationsModule {}
