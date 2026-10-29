import { Test, TestingModule } from '@nestjs/testing';
import { Logger } from '@nestjs/common';
import { NotificationsScheduler } from './notifications.scheduler';
import { NotificationsService } from './notifications.service';

describe('NotificationsScheduler - CU-69 (cron diario de retrasos)', () => {
  let scheduler: NotificationsScheduler;

  const serviceMock = {
    runOverdueCheck: jest.fn(),
  };

  beforeEach(async () => {
    jest.clearAllMocks();
    jest.restoreAllMocks();
    jest.useFakeTimers();
    delete process.env.NOTIFICATIONS_CRON_DISABLED;

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        NotificationsScheduler,
        { provide: NotificationsService, useValue: serviceMock },
      ],
    }).compile();

    scheduler = module.get<NotificationsScheduler>(NotificationsScheduler);
  });

  afterEach(() => {
    scheduler.onModuleDestroy();
    jest.useRealTimers();
    delete process.env.NOTIFICATIONS_CRON_DISABLED;
  });

  it('debería estar definido', () => {
    expect(scheduler).toBeDefined();
  });

  it('runNow() delega el chequeo en el servicio y devuelve el resultado', async () => {
    serviceMock.runOverdueCheck.mockResolvedValueOnce({ generadas: 4 });

    await expect(scheduler.runNow()).resolves.toEqual({ generadas: 4 });
    expect(serviceMock.runOverdueCheck).toHaveBeenCalledTimes(1);
  });

  it('onModuleInit() programa el cron cuando no está deshabilitado', () => {
    jest.spyOn(Logger.prototype, 'log').mockImplementation();

    scheduler.onModuleInit();

    expect(jest.getTimerCount()).toBe(1);
    expect(serviceMock.runOverdueCheck).not.toHaveBeenCalled();
  });

  it('con NOTIFICATIONS_CRON_DISABLED=true no programa timers ni consulta el servicio', () => {
    process.env.NOTIFICATIONS_CRON_DISABLED = 'true';

    scheduler.onModuleInit();

    expect(jest.getTimerCount()).toBe(0);
    jest.advanceTimersByTime(7 * 24 * 60 * 60 * 1000);
    expect(serviceMock.runOverdueCheck).not.toHaveBeenCalled();
  });

  it('onModuleDestroy() limpia los timers programados', () => {
    jest.spyOn(Logger.prototype, 'log').mockImplementation();

    scheduler.onModuleInit();
    expect(jest.getTimerCount()).toBe(1);

    scheduler.onModuleDestroy();

    expect(jest.getTimerCount()).toBe(0);
  });

  it('el disparo diario ejecuta el chequeo de retrasos', async () => {
    jest.spyOn(Logger.prototype, 'log').mockImplementation();
    serviceMock.runOverdueCheck.mockResolvedValue({ generadas: 1 });

    scheduler.onModuleInit();
    jest.advanceTimersByTime(24 * 60 * 60 * 1000);
    // Deja correr la microtarea encolada por el callback del timer.
    await Promise.resolve();

    expect(serviceMock.runOverdueCheck).toHaveBeenCalled();
  });
});
