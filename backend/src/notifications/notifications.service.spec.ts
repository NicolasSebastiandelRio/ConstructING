import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { BadRequestException, Logger, NotFoundException } from '@nestjs/common';
import { NotificationsService } from './notifications.service';
import { NotificationEntity } from './notification.entity';
import { NotificationPreferenceEntity } from './notification-preference.entity';
import { WorkEntity, WorkStatus } from '../works/entities/work.entity';

describe('NotificationsService - CU-67..CU-72 (Sprint 6)', () => {
  let service: NotificationsService;

  const notificationRepoMock = {
    create: jest.fn(),
    save: jest.fn(),
    find: jest.fn(),
    findOne: jest.fn(),
    count: jest.fn(),
  };
  const preferenceRepoMock = {
    create: jest.fn(),
    save: jest.fn(),
    findOne: jest.fn(),
  };
  const workRepoMock = {
    find: jest.fn(),
  };

  const obraVencida = {
    id: 'w1',
    nombre: 'Edificio Central',
    estado: WorkStatus.IN_PROGRESS,
    propietarioId: 'prop-1',
    fechaFinEstimada: '2026-01-10',
  };

  beforeEach(async () => {
    jest.clearAllMocks();
    jest.restoreAllMocks();

    notificationRepoMock.create.mockImplementation((data) => ({ ...data }));
    notificationRepoMock.save.mockImplementation((fila) =>
      Promise.resolve(fila),
    );
    notificationRepoMock.find.mockResolvedValue([]);
    preferenceRepoMock.create.mockImplementation((data) => ({ ...data }));
    preferenceRepoMock.save.mockImplementation((fila) =>
      Promise.resolve(fila),
    );
    preferenceRepoMock.findOne.mockResolvedValue({
      usuarioId: 'prop-1',
      recibirPorCorreo: true,
    });
    workRepoMock.find.mockResolvedValue([]);

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        NotificationsService,
        {
          provide: getRepositoryToken(NotificationEntity),
          useValue: notificationRepoMock,
        },
        {
          provide: getRepositoryToken(NotificationPreferenceEntity),
          useValue: preferenceRepoMock,
        },
        { provide: getRepositoryToken(WorkEntity), useValue: workRepoMock },
      ],
    }).compile();

    service = module.get<NotificationsService>(NotificationsService);
  });

  it('debería estar definido', () => {
    expect(service).toBeDefined();
  });

  describe('create (CU-67 paso 2 / CU-71 paso 2)', () => {
    const base = {
      id: 'n1',
      usuarioId: 'prop-1',
      tipo: 'avance',
      titulo: 'Avance de hito',
      mensaje: 'El hito Cimientos alcanzó el 100%.',
    };

    it('persiste la notificación en la bandeja in-app con el canal resuelto', async () => {
      const logSpy = jest.spyOn(Logger.prototype, 'log').mockImplementation();

      const result = await service.create(base);

      expect(notificationRepoMock.create).toHaveBeenCalledWith(
        expect.objectContaining({
          id: 'n1',
          usuarioId: 'prop-1',
          tipo: 'avance',
          titulo: 'Avance de hito',
          prioridad: 'normal',
          leida: false,
        }),
      );
      expect(notificationRepoMock.save).toHaveBeenCalled();
      expect(result.id).toBe('n1');
      expect(logSpy).toHaveBeenCalledWith(
        'CU-71: canal de correo ACTIVADO para prop-1',
      );
    });

    it('guarda igual en la bandeja aunque el correo esté desactivado (canal DESACTIVADO)', async () => {
      const logSpy = jest.spyOn(Logger.prototype, 'log').mockImplementation();
      preferenceRepoMock.findOne.mockResolvedValueOnce({
        usuarioId: 'prop-1',
        recibirPorCorreo: false,
      });

      await service.create(base);

      expect(notificationRepoMock.save).toHaveBeenCalled();
      expect(logSpy).toHaveBeenCalledWith(
        'CU-71: canal de correo DESACTIVADO para prop-1',
      );
    });

    it('rechaza el registro si falta algún campo obligatorio', async () => {
      await expect(
        service.create({ ...base, mensaje: '' }),
      ).rejects.toThrow(BadRequestException);
      await expect(
        service.create({ ...base, titulo: undefined as unknown as string }),
      ).rejects.toThrow(
        'El registro de notificación requiere destinatario, tipo, título y mensaje.',
      );
      expect(notificationRepoMock.save).not.toHaveBeenCalled();
    });
  });

  describe('listByUsuario (CU-70 paso 2)', () => {
    it('devuelve la bandeja del usuario en orden descendente', async () => {
      const filas = [{ id: 'n2' }, { id: 'n1' }];
      notificationRepoMock.find.mockResolvedValueOnce(filas);

      const result = await service.listByUsuario('prop-1');

      expect(notificationRepoMock.find).toHaveBeenCalledWith({
        where: { usuarioId: 'prop-1' },
        order: { createdAt: 'DESC' },
      });
      expect(result).toBe(filas);
    });
  });

  describe('countUnread (CU-72 badge)', () => {
    it('cuenta sólo las no leídas del usuario', async () => {
      notificationRepoMock.count.mockResolvedValueOnce(2);

      await expect(service.countUnread('prop-1')).resolves.toBe(2);
      expect(notificationRepoMock.count).toHaveBeenCalledWith({
        where: { usuarioId: 'prop-1', leida: false },
      });
    });
  });

  describe('markAsRead (CU-72)', () => {
    it('marca la notificación como leída', async () => {
      notificationRepoMock.findOne.mockResolvedValueOnce({
        id: 'n1',
        usuarioId: 'prop-1',
        leida: false,
      });

      const result = await service.markAsRead('n1');

      expect(notificationRepoMock.save).toHaveBeenCalledWith(
        expect.objectContaining({ id: 'n1', leida: true }),
      );
      expect(result.leida).toBe(true);
    });

    it('lanza NotFound si la notificación no existe', async () => {
      notificationRepoMock.findOne.mockResolvedValueOnce(null);

      await expect(service.markAsRead('fantasma')).rejects.toThrow(
        new NotFoundException('La notificación fantasma no fue encontrada.'),
      );
      expect(notificationRepoMock.save).not.toHaveBeenCalled();
    });
  });

  describe('getPreferences (CU-71)', () => {
    it('crea la preferencia por defecto (correo activado) cuando no existe', async () => {
      preferenceRepoMock.findOne.mockResolvedValueOnce(null);

      const result = await service.getPreferences('u-nuevo');

      expect(preferenceRepoMock.create).toHaveBeenCalledWith({
        usuarioId: 'u-nuevo',
        recibirPorCorreo: true,
      });
      expect(preferenceRepoMock.save).toHaveBeenCalled();
      expect(result.recibirPorCorreo).toBe(true);
    });

    it('devuelve la preferencia existente sin crear otra fila', async () => {
      preferenceRepoMock.findOne.mockResolvedValueOnce({
        usuarioId: 'prop-1',
        recibirPorCorreo: false,
      });

      const result = await service.getPreferences('prop-1');

      expect(result.recibirPorCorreo).toBe(false);
      expect(preferenceRepoMock.create).not.toHaveBeenCalled();
      expect(preferenceRepoMock.save).not.toHaveBeenCalled();
    });
  });

  describe('updatePreferences (CU-71 paso 2)', () => {
    it('persiste el booleano elegido y devuelve la fila', async () => {
      preferenceRepoMock.findOne.mockResolvedValueOnce({
        usuarioId: 'prop-1',
        recibirPorCorreo: true,
      });

      const result = await service.updatePreferences('prop-1', false);

      expect(preferenceRepoMock.save).toHaveBeenCalledWith(
        expect.objectContaining({ usuarioId: 'prop-1', recibirPorCorreo: false }),
      );
      expect(result.recibirPorCorreo).toBe(false);
    });

    it('crea la fila con el valor deseado si el usuario no tenía preferencia', async () => {
      preferenceRepoMock.findOne.mockResolvedValueOnce(null);

      const result = await service.updatePreferences('u-nuevo', false);

      expect(result.usuarioId).toBe('u-nuevo');
      expect(result.recibirPorCorreo).toBe(false);
    });
  });

  describe('runOverdueCheck (CU-69)', () => {
    const ahora = new Date('2026-06-15T10:00:00');

    it('genera una alerta de retraso para la obra En Ejecución vencida', async () => {
      workRepoMock.find.mockResolvedValueOnce([{ ...obraVencida }]);

      const result = await service.runOverdueCheck(ahora);

      expect(workRepoMock.find).toHaveBeenCalledTimes(1);
      expect(result).toEqual({ generadas: 1 });
      expect(notificationRepoMock.save).toHaveBeenCalledWith(
        expect.objectContaining({
          usuarioId: 'prop-1',
          tipo: 'retraso',
          prioridad: 'alta',
          titulo: 'Alerta de retraso',
          obraId: 'w1',
          mensaje:
            'La obra "Edificio Central" superó su fecha de fin estimada (2026-01-10) sin completarse.',
        }),
      );
      const guardada = notificationRepoMock.save.mock.calls[0][0];
      expect(guardada.id).toMatch(/^[0-9a-f-]{36}$/i);
    });

    it('consulta únicamente obras En Ejecución con fecha de fin estimada', async () => {
      await service.runOverdueCheck(ahora);

      const filtro = workRepoMock.find.mock.calls[0][0];
      expect(filtro.where.estado).toBe(WorkStatus.IN_PROGRESS);
      expect(filtro.where.fechaFinEstimada).toBeDefined();
    });

    it('no genera alertas cuando la obra está Completada o Archivada', async () => {
      // El filtro de estado lo aplica la consulta: Completado/Archivado no
      // aparecen en el resultado.
      workRepoMock.find.mockResolvedValueOnce([]);

      const result = await service.runOverdueCheck(ahora);

      expect(result).toEqual({ generadas: 0 });
      expect(notificationRepoMock.save).not.toHaveBeenCalled();
    });

    it('no genera alertas si la obra no tiene fecha de fin estimada', async () => {
      workRepoMock.find.mockResolvedValueOnce([
        { ...obraVencida, fechaFinEstimada: null },
      ]);

      const result = await service.runOverdueCheck(ahora);

      expect(result).toEqual({ generadas: 0 });
      expect(notificationRepoMock.save).not.toHaveBeenCalled();
    });

    it('no alerta si la fecha de fin estimada todavía no pasó (mismo día inclusive)', async () => {
      workRepoMock.find.mockResolvedValueOnce([
        { ...obraVencida, fechaFinEstimada: '2026-06-15' },
      ]);

      const result = await service.runOverdueCheck(ahora);

      expect(result).toEqual({ generadas: 0 });
      expect(notificationRepoMock.save).not.toHaveBeenCalled();
    });

    it('no duplica la alerta si la misma obra ya fue alertada en las últimas 24 h', async () => {
      workRepoMock.find.mockResolvedValueOnce([{ ...obraVencida }]);
      notificationRepoMock.find.mockResolvedValueOnce([
        {
          id: 'n-previa',
          tipo: 'retraso',
          obraId: 'w1',
          createdAt: new Date('2026-06-15T06:00:00'),
        },
      ]);

      const result = await service.runOverdueCheck(ahora);

      expect(result).toEqual({ generadas: 0 });
      expect(notificationRepoMock.save).not.toHaveBeenCalled();
      const busqueda = notificationRepoMock.find.mock.calls[0][0];
      expect(busqueda.where.tipo).toBe('retraso');
      expect(busqueda.where.createdAt).toBeDefined();
    });

    it('sí alerta obras distintas de la ya notificada', async () => {
      workRepoMock.find.mockResolvedValueOnce([
        { ...obraVencida },
        { ...obraVencida, id: 'w2', nombre: 'Torre Norte' },
      ]);
      notificationRepoMock.find.mockResolvedValueOnce([
        {
          id: 'n-previa',
          tipo: 'retraso',
          obraId: 'w1',
          createdAt: new Date('2026-06-15T06:00:00'),
        },
      ]);

      const result = await service.runOverdueCheck(ahora);

      expect(result).toEqual({ generadas: 1 });
      expect(notificationRepoMock.save).toHaveBeenCalledWith(
        expect.objectContaining({ obraId: 'w2' }),
      );
    });
  });
});
