import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { IsNull, MoreThanOrEqual, Not, Repository } from 'typeorm';
import { randomUUID } from 'crypto';
import { NotificationEntity } from './notification.entity';
import { NotificationPreferenceEntity } from './notification-preference.entity';
import { WorkEntity, WorkStatus } from '../works/entities/work.entity';

export interface CreateNotificationInput {
  id: string;
  usuarioId: string;
  tipo: string;
  titulo: string;
  mensaje: string;
  obraId?: string | null;
  hitoId?: string | null;
  prioridad?: string;
}

/**
 * Servicio de notificaciones del Sprint 6 (CU-67..CU-72).
 *
 * - CU-67: generación de avisos de avance (bandeja in-app).
 * - CU-69: detección de retrasos (cron diario) por fecha de fin estimada.
 * - CU-70: consulta de la bandeja del usuario (más recientes primero).
 * - CU-71: preferencias de canal de correo (in-app siempre obligatorio).
 * - CU-72: marca de leída y contador de pendientes (badge).
 */
@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    @InjectRepository(NotificationEntity)
    private readonly notificationRepository: Repository<NotificationEntity>,
    @InjectRepository(NotificationPreferenceEntity)
    private readonly preferenceRepository: Repository<NotificationPreferenceEntity>,
    @InjectRepository(WorkEntity)
    private readonly workRepository: Repository<WorkEntity>,
  ) {}

  /**
   * CU-67 paso 2 / CU-71 paso 2: resuelve el canal antes de persistir.
   *
   * La notificación se guarda SIEMPRE en la bandeja in-app; la preferencia
   * del destinatario sólo decide si además se dispara el correo. El canal
   * resuelto queda en el log para trazabilidad.
   */
  async create(input: CreateNotificationInput): Promise<NotificationEntity> {
    // Defensa en profundidad: el id es la clave de la fila (lo genera el
    // emisor del evento o el cron), por eso también es obligatorio.
    if (
      !input?.id ||
      !input?.usuarioId ||
      !input?.tipo ||
      !input?.titulo ||
      !input?.mensaje
    ) {
      throw new BadRequestException(
        'El registro de notificación requiere destinatario, tipo, título y mensaje.',
      );
    }

    const preferencia = await this.getPreferences(input.usuarioId);
    this.logger.log(
      `CU-71: canal de correo ${
        preferencia.recibirPorCorreo ? 'ACTIVADO' : 'DESACTIVADO'
      } para ${input.usuarioId}`,
    );

    const fila = this.notificationRepository.create({
      id: input.id,
      usuarioId: input.usuarioId,
      tipo: input.tipo,
      titulo: input.titulo,
      mensaje: input.mensaje,
      obraId: input.obraId ?? null,
      hitoId: input.hitoId ?? null,
      prioridad: input.prioridad ?? 'normal',
      leida: false,
    });
    return this.notificationRepository.save(fila);
  }

  /**
   * CU-70 paso 2: bandeja del usuario en orden descendente (los avisos más
   * recientes primero).
   */
  async listByUsuario(usuarioId: string): Promise<NotificationEntity[]> {
    return this.notificationRepository.find({
      where: { usuarioId },
      order: { createdAt: 'DESC' },
    });
  }

  /** CU-72: contador de no leídas para el badge de la campana. */
  async countUnread(usuarioId: string): Promise<number> {
    return this.notificationRepository.count({
      where: { usuarioId, leida: false },
    });
  }

  /** CU-72: marca un aviso como leído. */
  async markAsRead(id: string): Promise<NotificationEntity> {
    const fila = await this.notificationRepository.findOne({ where: { id } });
    if (!fila) {
      throw new NotFoundException(`La notificación ${id} no fue encontrada.`);
    }
    fila.leida = true;
    return this.notificationRepository.save(fila);
  }

  /**
   * CU-71: preferencia del usuario. Si todavía no tiene fila, se crea con el
   * valor por defecto (recibir por correo) y se devuelve.
   */
  async getPreferences(
    usuarioId: string,
  ): Promise<NotificationPreferenceEntity> {
    const existente = await this.preferenceRepository.findOne({
      where: { usuarioId },
    });
    if (existente) {
      return existente;
    }
    const nueva = this.preferenceRepository.create({
      usuarioId,
      recibirPorCorreo: true,
    });
    return this.preferenceRepository.save(nueva);
  }

  /** CU-71 paso 2: persiste el canal de correo elegido por el usuario. */
  async updatePreferences(
    usuarioId: string,
    recibirPorCorreo: boolean,
  ): Promise<NotificationPreferenceEntity> {
    const preferencia = await this.getPreferences(usuarioId);
    preferencia.recibirPorCorreo = recibirPorCorreo;
    return this.preferenceRepository.save(preferencia);
  }

  /**
   * CU-69: chequeo de obras en ejecución vencidas.
   *
   * Genera UNA alerta de retraso por obra cuya `fechaFinEstimada`
   * ('YYYY-MM-DD', comparada por día local) ya pasó y que sigue En Ejecución.
   * La idempotencia es diaria: si la misma obra ya recibió una alerta de
   * retraso en las últimas 24 h, no se repite (el cron corre a diario).
   */
  async runOverdueCheck(now?: Date): Promise<{ generadas: number }> {
    const referencia = now ?? new Date();
    const hoyLocal = this.toLocalIsoDate(referencia);

    const obras = await this.workRepository.find({
      where: {
        estado: WorkStatus.IN_PROGRESS,
        fechaFinEstimada: Not(IsNull()),
      },
    });

    const desde = new Date(referencia.getTime() - 24 * 60 * 60 * 1000);
    const alertasRecientes = await this.notificationRepository.find({
      where: { tipo: 'retraso', createdAt: MoreThanOrEqual(desde) },
    });
    const obrasYaAlertadas = new Set(
      alertasRecientes.map((a) => a.obraId).filter((id): id is string => !!id),
    );

    let generadas = 0;
    for (const obra of obras) {
      const fechaFin = obra.fechaFinEstimada;
      if (!fechaFin) {
        continue;
      }
      // Comparación por día en formato ISO: 'YYYY-MM-DD' < 'YYYY-MM-DD'.
      if (fechaFin >= hoyLocal) {
        continue;
      }
      if (obrasYaAlertadas.has(obra.id)) {
        continue;
      }

      await this.create({
        id: randomUUID(),
        usuarioId: obra.propietarioId,
        tipo: 'retraso',
        titulo: 'Alerta de retraso',
        mensaje: `La obra "${obra.nombre}" superó su fecha de fin estimada (${fechaFin}) sin completarse.`,
        obraId: obra.id,
        prioridad: 'alta',
      });
      obrasYaAlertadas.add(obra.id);
      generadas += 1;
    }

    return { generadas };
  }

  /** Fecha local (no UTC) en formato 'YYYY-MM-DD'. */
  private toLocalIsoDate(fecha: Date): string {
    const mes = `${fecha.getMonth() + 1}`.padStart(2, '0');
    const dia = `${fecha.getDate()}`.padStart(2, '0');
    return `${fecha.getFullYear()}-${mes}-${dia}`;
  }
}
