import { MailerService } from '@nestjs-modules/mailer';
import { Test, TestingModule } from '@nestjs/testing';
import { MailRetryQueueService } from './mail-retry-queue.service';

describe('MailRetryQueueService - CU-12 (Enviar correo de bienvenida automática)', () => {
  let service: MailRetryQueueService;
  const mailerSendMock = jest.fn();

  beforeEach(async () => {
    jest.clearAllMocks();
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        MailRetryQueueService,
        { provide: MailerService, useValue: { sendMail: mailerSendMock } },
      ],
    }).compile();

    service = module.get<MailRetryQueueService>(MailRetryQueueService);
  });

  afterEach(() => {
    // Garantiza que el timer no pinche el proceso de testing.
    (service as unknown as { stopTimer: () => void }).stopTimer();
  });

  it('despacha el correo directamente si SMTP responde', async () => {
    mailerSendMock.mockResolvedValue(true);

    await service.sendWithRetry({ to: 'a@gmail.com', subject: 'Hola', text: 'Bienvenido' });

    expect(mailerSendMock).toHaveBeenCalledWith(
      expect.objectContaining({ to: 'a@gmail.com', subject: 'Hola', text: 'Bienvenido' }),
    );
    expect(service.pendingCount).toBe(0);
  });

  it('Flujo Alt. 4.2: encola el correo cuando SMTP falla para reintentarlo después', async () => {
    mailerSendMock.mockRejectedValue(new Error('timeout'));
    mailerSendMock.mockClear();

    await service.sendWithRetry({ to: 'b@gmail.com', subject: 'Hola', text: 'Bienvenido' });

    // No debe propagar el error, sino encolar.
    expect(service.pendingCount).toBe(1);
  });

  it('reintenta el correo encolado y lo elimina de la cola si tiene éxito', async () => {
    mailerSendMock.mockRejectedValueOnce(new Error('timeout')); // primer intento falla
    mailerSendMock.mockResolvedValueOnce(true); // reintento exitoso

    await service.sendWithRetry({ to: 'c@gmail.com', subject: 'Hola', text: 'Bienvenido' });
    expect(service.pendingCount).toBe(1);

    // Fuerza el flush del temporizador llamando internamente a la cola.
    await (service as unknown as { flush: () => Promise<void> }).flush();

    expect(service.pendingCount).toBe(0);
    expect(mailerSendMock).toHaveBeenCalledTimes(2);
  });

  it('aplica el intervalo de 5 minutos especificado en el flujo alterno', () => {
    expect(MailRetryQueueService.RETRY_INTERVAL_MS).toBe(5 * 60 * 1000);
  });
});