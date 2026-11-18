import { Test, TestingModule } from '@nestjs/testing';
import { BadRequestException } from '@nestjs/common';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';

describe('NotificationsController - CU-67..CU-72', () => {
  let controller: NotificationsController;
  let service: NotificationsService;

  const notificacion = {
    id: 'n1',
    usuarioId: 'prop-1',
    tipo: 'avance',
    titulo: 'Avance de hito',
    mensaje: 'El hito Cimientos alcanzó el 100%.',
    obraId: 'w1',
    hitoId: null,
    prioridad: 'normal',
    leida: false,
    createdAt: new Date('2026-06-15T10:00:00Z'),
  };

  const serviceMock = {
    create: jest.fn(),
    listByUsuario: jest.fn(),
    countUnread: jest.fn(),
    markAsRead: jest.fn(),
    getPreferences: jest.fn(),
    updatePreferences: jest.fn(),
    runOverdueCheck: jest.fn(),
  };

  beforeEach(async () => {
    jest.clearAllMocks();
    const module: TestingModule = await Test.createTestingModule({
      controllers: [NotificationsController],
      providers: [{ provide: NotificationsService, useValue: serviceMock }],
    }).compile();

    controller = module.get<NotificationsController>(NotificationsController);
    service = module.get<NotificationsService>(NotificationsService);
  });

  it('debería estar definido', () => {
    expect(controller).toBeDefined();
  });

  it('POST /notifications delega en el servicio (CU-67)', async () => {
    const input = {
      id: 'n1',
      usuarioId: 'prop-1',
      tipo: 'avance',
      titulo: 'Avance de hito',
      mensaje: 'El hito Cimientos alcanzó el 100%.',
    };
    serviceMock.create.mockResolvedValue(notificacion);

    const result = await controller.create(input);

    expect(service.create).toHaveBeenCalledWith(input);
    expect(result).toMatchObject({ id: 'n1', tipo: 'avance' });
  });

  it('POST /notifications sin campos obligatorios → 400', () => {
    expect(() =>
      controller.create({ id: 'n1', usuarioId: 'prop-1' } as never),
    ).toThrow(BadRequestException);
    expect(() =>
      controller.create({
        id: 'n1',
        usuarioId: 'prop-1',
        tipo: 'avance',
        titulo: 'Avance',
      } as never),
    ).toThrow('Falta el campo obligatorio: mensaje.');
    expect(serviceMock.create).not.toHaveBeenCalled();
  });

  it('GET /notifications/usuario/:usuarioId delega en el servicio (CU-70)', async () => {
    serviceMock.listByUsuario.mockResolvedValue([notificacion]);

    const result = await controller.listByUsuario('prop-1');

    expect(service.listByUsuario).toHaveBeenCalledWith('prop-1');
    expect(result).toHaveLength(1);
  });

  it('GET /notifications/pendientes/:usuarioId devuelve { noLeidas } (CU-72)', async () => {
    serviceMock.countUnread.mockResolvedValue(3);

    const result = await controller.countUnread('prop-1');

    expect(service.countUnread).toHaveBeenCalledWith('prop-1');
    expect(result).toEqual({ noLeidas: 3 });
  });

  it('PATCH /notifications/:id/leida delega en el servicio (CU-72)', async () => {
    serviceMock.markAsRead.mockResolvedValue({ ...notificacion, leida: true });

    const result = await controller.markAsRead('n1');

    expect(service.markAsRead).toHaveBeenCalledWith('n1');
    expect(result.leida).toBe(true);
  });

  it('GET /notifications/preferencias/:usuarioId delega en el servicio (CU-71)', async () => {
    serviceMock.getPreferences.mockResolvedValue({
      usuarioId: 'prop-1',
      recibirPorCorreo: true,
    });

    const result = await controller.getPreferences('prop-1');

    expect(service.getPreferences).toHaveBeenCalledWith('prop-1');
    expect(result.recibirPorCorreo).toBe(true);
  });

  it('PATCH /notifications/preferencias/:usuarioId persiste el booleano (CU-71)', async () => {
    serviceMock.updatePreferences.mockResolvedValue({
      usuarioId: 'prop-1',
      recibirPorCorreo: false,
    });

    const result = await controller.updatePreferences('prop-1', {
      recibirPorCorreo: false,
    });

    expect(service.updatePreferences).toHaveBeenCalledWith('prop-1', false);
    expect(result.recibirPorCorreo).toBe(false);
  });

  it('PATCH preferencias con un valor no booleano → 400', () => {
    expect(() =>
      controller.updatePreferences('prop-1', { recibirPorCorreo: 'si' }),
    ).toThrow(
      new BadRequestException('El campo recibirPorCorreo debe ser booleano.'),
    );
    expect(serviceMock.updatePreferences).not.toHaveBeenCalled();
  });

  it('PATCH preferencias sin el campo → 400', () => {
    expect(() => controller.updatePreferences('prop-1', {})).toThrow(
      BadRequestException,
    );
    expect(serviceMock.updatePreferences).not.toHaveBeenCalled();
  });

  it('POST /notifications/cron/retrasos dispara el chequeo manual (CU-69)', async () => {
    serviceMock.runOverdueCheck.mockResolvedValue({ generadas: 2 });

    const result = await controller.runOverdueCheck();

    expect(service.runOverdueCheck).toHaveBeenCalled();
    expect(result).toEqual({ generadas: 2 });
  });
});
