import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { NotificationsService } from './notifications.service';

/** Hora local a la que corre el chequeo diario de retrasos (CU-69). */
const CRON_HOUR = 6;

/** Una jornada completa: el cron se reprograma cada 24 h. */
const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * CU-69: Cron Job diario del chequeo de retrasos.
 *
 * Implementado con `setTimeout` + `setInterval` nativos (sin `@nestjs/schedule`)
 * para no agregar dependencias: el primer disparo se agenda a las 06:00 hora
 * local y a partir de allí se repite cada 24 h. `NOTIFICATIONS_CRON_DISABLED=true`
 * apaga el cron (tests y disparos manuales por endpoint).
 */
@Injectable()
export class NotificationsScheduler implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(NotificationsScheduler.name);

  private timeoutHandle?: NodeJS.Timeout;
  private intervalHandle?: NodeJS.Timeout;

  constructor(private readonly notificationsService: NotificationsService) {}

  onModuleInit(): void {
    if (process.env.NOTIFICATIONS_CRON_DISABLED === 'true') {
      this.logger.log(
        'CU-69: cron de retrasos deshabilitado por configuración.',
      );
      return;
    }

    const espera = this.msHastaProximaEjecucion(new Date());
    this.timeoutHandle = setTimeout(() => {
      void this.runOverdueCheck();
      this.intervalHandle = setInterval(() => {
        void this.runOverdueCheck();
      }, DAY_MS);
      this.intervalHandle.unref?.();
    }, espera);
    // No mantiene vivo el proceso sólo por el cron.
    this.timeoutHandle.unref?.();

    this.logger.log(
      `CU-69: chequeo diario de retrasos agendado en ${Math.round(espera / 1000)}s.`,
    );
  }

  onModuleDestroy(): void {
    if (this.timeoutHandle) {
      clearTimeout(this.timeoutHandle);
      this.timeoutHandle = undefined;
    }
    if (this.intervalHandle) {
      clearInterval(this.intervalHandle);
      this.intervalHandle = undefined;
    }
  }

  /**
   * Disparo inmediato del chequeo (endpoint manual `POST /notifications/cron/retrasos`
   * y tests), sin esperar al cron.
   */
  async runNow(): Promise<{ generadas: number }> {
    return this.notificationsService.runOverdueCheck();
  }

  private async runOverdueCheck(): Promise<void> {
    await this.notificationsService.runOverdueCheck();
    this.logger.log('CU-69: chequeo diario de retrasos ejecutado');
  }

  /** Milisegundos hasta la próxima ocurrencia de las 06:00 locales. */
  private msHastaProximaEjecucion(ahora: Date): number {
    const proxima = new Date(ahora.getTime());
    proxima.setHours(CRON_HOUR, 0, 0, 0);
    if (proxima.getTime() <= ahora.getTime()) {
      proxima.setDate(proxima.getDate() + 1);
    }
    return proxima.getTime() - ahora.getTime();
  }
}
