import { Injectable, Logger } from '@nestjs/common';
import { MailerService } from '@nestjs-modules/mailer';

export interface QueuedMail {
  to: string;
  subject: string;
  text: string;
  attempts: number;
}

/**
 * CU-12 Flujo Alterno 4.1/4.2: si falla la conexión con el servidor SMTP, el
 * correo se encola en un proceso asíncrono que reintenta el envío
 * automáticamente cada 5 minutos hasta lograrlo (o hasta agotar los intentos).
 */
@Injectable()
export class MailRetryQueueService {
  private readonly logger = new Logger(MailRetryQueueService.name);
  private readonly queue: QueuedMail[] = [];
  private timer: NodeJS.Timeout | null = null;

  /** Intervalo de reintento según la especificación (cada 5 minutos). */
  static readonly RETRY_INTERVAL_MS = 5 * 60 * 1000;
  /** Número máximo de reintentos antes de descartar el correo. */
  static readonly MAX_ATTEMPTS = 3;
  /** Tope acotado de la cola para evitar crecimiento descontrolado en memoria. */
  static readonly MAX_QUEUE_SIZE = 100;

  constructor(private readonly mailerService: MailerService) {}

  /**
   * Intenta despachar el correo una vez. Si SMTP falla, lo encola para el
   * reintento automático cada 5 minutos. Nunca lanza hacia el llamador.
   */
  async sendWithRetry(mail: Omit<QueuedMail, 'attempts'>): Promise<void> {
    try {
      await this.mailerService.sendMail(mail);
    } catch (error) {
      this.logger.warn('No se pudo despachar el correo SMTP; se encola para reintento (CU-12 4.2).');
      this.enqueue({ ...mail, attempts: 0 });
    }
  }

  private enqueue(mail: QueuedMail): void {
    if (this.queue.length >= MailRetryQueueService.MAX_QUEUE_SIZE) {
      this.logger.error('Cola de correos llena; se descarta el envío para evitar saturación.');
      return;
    }
    this.queue.push(mail);
    this.startTimer();
  }

  private startTimer(): void {
    if (this.timer) return;
    this.timer = setInterval(
      () => void this.flush(),
      MailRetryQueueService.RETRY_INTERVAL_MS,
    );
    // El timer no debe mantener vivo el proceso (tests E2E / apagado limpio).
    if (typeof this.timer.unref === 'function') {
      this.timer.unref();
    }
  }

  private async flush(): Promise<void> {
    const pending = [...this.queue];
    this.queue.length = 0;

    for (const mail of pending) {
      try {
        await this.mailerService.sendMail(mail);
        this.logger.log(`Correo reenviado a ${mail.to} tras reintento exitoso.`);
      } catch (error) {
        mail.attempts += 1;
        if (mail.attempts >= MailRetryQueueService.MAX_ATTEMPTS) {
          this.logger.error(`Correo a ${mail.to} descartado tras agotar los reintentos (CU-12 4.2).`);
        } else {
          this.queue.push(mail);
        }
      }
    }

    if (this.queue.length === 0) {
      this.stopTimer();
    }
  }

  private stopTimer(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  /** Expone la cantidad de correos pendientes (diagnóstico / tests). */
  get pendingCount(): number {
    return this.queue.length;
  }
}