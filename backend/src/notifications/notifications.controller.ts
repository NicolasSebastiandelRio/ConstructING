import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
} from '@nestjs/common';
import { NotificationEntity } from './notification.entity';
import { NotificationPreferenceEntity } from './notification-preference.entity';
import {
  CreateNotificationInput,
  NotificationsService,
} from './notifications.service';

/**
 * Endpoints de notificaciones (CU-67..CU-72).
 *
 * Sin prefijo global, igual que `AuditLogController`. El orden de declaración
 * importa: las rutas específicas (`pendientes`, `preferencias`, `usuario`,
 * `cron`) se declaran antes que cualquier `:id` para que Nest no las capture
 * como parámetro dinámico.
 */
@Controller()
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  /** CU-67: registra un aviso en la bandeja del destinatario. */
  @Post('notifications')
  create(@Body() input: CreateNotificationInput): Promise<NotificationEntity> {
    for (const key of ['id', 'usuarioId', 'tipo', 'titulo', 'mensaje']) {
      if (!input?.[key as keyof CreateNotificationInput]) {
        throw new BadRequestException(
          `Falta el campo obligatorio: ${key}.`,
        );
      }
    }
    return this.notificationsService.create(input);
  }

  /** CU-72: badge de pendientes (no leídas). */
  @Get('notifications/pendientes/:usuarioId')
  async countUnread(
    @Param('usuarioId') usuarioId: string,
  ): Promise<{ noLeidas: number }> {
    const noLeidas = await this.notificationsService.countUnread(usuarioId);
    return { noLeidas };
  }

  /** CU-71: preferencias de canal de correo del usuario. */
  @Get('notifications/preferencias/:usuarioId')
  getPreferences(
    @Param('usuarioId') usuarioId: string,
  ): Promise<NotificationPreferenceEntity> {
    return this.notificationsService.getPreferences(usuarioId);
  }

  /** CU-71 paso 2: actualiza el canal de correo. */
  @Patch('notifications/preferencias/:usuarioId')
  updatePreferences(
    @Param('usuarioId') usuarioId: string,
    @Body() body: { recibirPorCorreo?: unknown },
  ): Promise<NotificationPreferenceEntity> {
    if (typeof body?.recibirPorCorreo !== 'boolean') {
      throw new BadRequestException(
        'El campo recibirPorCorreo debe ser booleano.',
      );
    }
    return this.notificationsService.updatePreferences(
      usuarioId,
      body.recibirPorCorreo,
    );
  }

  /** CU-70 paso 2: bandeja del usuario, más recientes primero. */
  @Get('notifications/usuario/:usuarioId')
  listByUsuario(
    @Param('usuarioId') usuarioId: string,
  ): Promise<NotificationEntity[]> {
    return this.notificationsService.listByUsuario(usuarioId);
  }

  /** CU-69: disparo manual del chequeo de retrasos (QA). */
  @Post('notifications/cron/retrasos')
  runOverdueCheck(): Promise<{ generadas: number }> {
    return this.notificationsService.runOverdueCheck();
  }

  /** CU-72: marca un aviso como leído. */
  @Patch('notifications/:id/leida')
  markAsRead(@Param('id') id: string): Promise<NotificationEntity> {
    return this.notificationsService.markAsRead(id);
  }
}
