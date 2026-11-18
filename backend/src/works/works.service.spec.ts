import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { BadRequestException } from '@nestjs/common';
import { WorksService } from './works.service';
import { WorkEntity, WorkStatus } from './entities/work.entity';
import { UserEntity } from '../auth/user.entity';

describe('WorksService - CU-13 (Crear Nueva Obra)', () => {
  let service: WorksService;

  const workRepoMock = {
    create: jest.fn(),
    save: jest.fn(),
    find: jest.fn(),
    findOne: jest.fn(),
    softDelete: jest.fn(),
  };
  const userRepoMock = {
    findOne: jest.fn(),
  };

  const propietario = { id: 'prop-1', email: 'dueño@gmail.com', role: 'Propietario' };

  beforeEach(async () => {
    jest.clearAllMocks();
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        WorksService,
        { provide: getRepositoryToken(WorkEntity), useValue: workRepoMock },
        { provide: getRepositoryToken(UserEntity), useValue: userRepoMock },
      ],
    }).compile();

    service = module.get<WorksService>(WorksService);
  });

  it('debería estar definido', () => {
    expect(service).toBeDefined();
  });

  describe('create (CU-13 Flujo Normal + CU-14)', () => {
    const baseDto = {
      nombre: 'Edificio Central',
      direccion: 'Av. Libertador 1234',
      fechaInicio: '2026-09-01',
      descripcion: 'Torre residencial',
    };

    it('vincula al propietario por correo y crea la obra En Planificación', async () => {
      userRepoMock.findOne.mockResolvedValueOnce(propietario);
      workRepoMock.create.mockImplementation((data) => ({ id: 'w1', ...data }));
      workRepoMock.save.mockImplementation((w) => Promise.resolve(w));

      const result = await service.create({ ...baseDto, propietarioEmail: 'dueño@gmail.com' });

      expect(userRepoMock.findOne).toHaveBeenCalledWith({ where: { email: 'dueño@gmail.com' } });
      expect(workRepoMock.create).toHaveBeenCalledWith(
        expect.objectContaining({
          nombre: 'Edificio Central',
          estado: WorkStatus.PLANIFICATION,
          propietarioId: 'prop-1',
        }),
      );
      expect(result.estado).toBe(WorkStatus.PLANIFICATION);
      expect(result.propietarioId).toBe('prop-1');
    });

    it('vincula al propietario por ID cuando no se informa el correo', async () => {
      userRepoMock.findOne.mockResolvedValueOnce(propietario);
      workRepoMock.create.mockImplementation((data) => ({ id: 'w2', ...data }));
      workRepoMock.save.mockImplementation((w) => Promise.resolve(w));

      const result = await service.create({ ...baseDto, propietarioId: 'prop-1' });

      expect(userRepoMock.findOne).toHaveBeenCalledWith({ where: { id: 'prop-1' } });
      expect(result.propietarioId).toBe('prop-1');
    });

    it('rechaza la creación si el propietario no existe (CU-14 Alt. 2.1)', async () => {
      userRepoMock.findOne.mockResolvedValueOnce(null);

      await expect(
        service.create({ ...baseDto, propietarioEmail: 'fantasma@gmail.com' }),
      ).rejects.toThrow(BadRequestException);
      expect(workRepoMock.save).not.toHaveBeenCalled();
    });

    it('rechaza la creación si no se informa ningún identificador de propietario', async () => {
      await expect(service.create({ ...baseDto })).rejects.toThrow(BadRequestException);
      expect(userRepoMock.findOne).not.toHaveBeenCalled();
      expect(workRepoMock.save).not.toHaveBeenCalled();
    });

    it('CU-15 paso 4: vincula las coordenadas al registro de la obra', async () => {
      userRepoMock.findOne.mockResolvedValueOnce(propietario);
      workRepoMock.create.mockImplementation((data) => ({ id: 'w3', ...data }));
      workRepoMock.save.mockImplementation((w) => Promise.resolve(w));

      const result = await service.create({
        ...baseDto,
        propietarioEmail: 'dueño@gmail.com',
        latitud: -34.6037,
        longitud: -58.3816,
      });

      expect(workRepoMock.create).toHaveBeenCalledWith(
        expect.objectContaining({ latitud: -34.6037, longitud: -58.3816 }),
      );
      expect(result.latitud).toBe(-34.6037);
      expect(result.longitud).toBe(-58.3816);
    });
  });

  describe('findAll (CU-18 Consultar Obras Asignadas)', () => {
    it('sin filtro devuelve el listado general excluyendo archivadas', async () => {
      workRepoMock.find.mockResolvedValueOnce([]);

      await service.findAll();

      expect(workRepoMock.find).toHaveBeenCalledWith({
        where: {},
        relations: { propietario: true },
        withDeleted: false,
      });
    });

    it('con propietarioId filtra "Mis Obras" del propietario', async () => {
      workRepoMock.find.mockResolvedValueOnce([]);

      await service.findAll('prop-1');

      expect(workRepoMock.find).toHaveBeenCalledWith({
        where: { propietarioId: 'prop-1' },
        relations: { propietario: true },
        withDeleted: false,
      });
    });

    it('con archivedOnly trae sólo el historial de archivadas (CU-21)', async () => {
      workRepoMock.find.mockResolvedValueOnce([]);

      await service.findAll(undefined, true);

      expect(workRepoMock.find).toHaveBeenCalledWith({
        where: { deletedAt: expect.anything() },
        relations: { propietario: true },
        withDeleted: true,
      });
    });
  });

  describe('update con re-vinculación (CU-14 desde la edición de obra)', () => {
    const obra = {
      id: 'w1',
      nombre: 'Edificio Central',
      direccion: 'Av. Libertador 1234',
      fechaInicio: '2026-09-01',
      estado: WorkStatus.PLANIFICATION,
      propietarioId: 'prop-1',
    };

    it('re-vincula al propietario por correo verificando su existencia', async () => {
      const nuevo = { id: 'prop-2', email: 'nuevo@gmail.com', role: 'Propietario' };
      workRepoMock.findOne.mockResolvedValueOnce({ ...obra });
      userRepoMock.findOne.mockResolvedValueOnce(nuevo);
      workRepoMock.save.mockImplementation((w) => Promise.resolve(w));

      const result = await service.update('w1', { propietarioEmail: 'nuevo@gmail.com' } as never);

      expect(userRepoMock.findOne).toHaveBeenCalledWith({ where: { email: 'nuevo@gmail.com' } });
      expect(result.propietarioId).toBe('prop-2');
      // El campo virtual nunca debe persistirse en la entidad.
      expect(result).not.toHaveProperty('propietarioEmail');
      // La relación debe actualizarse junto con la FK: TypeORM deriva la
      // columna del objeto cargado al guardar (si no, ignora el cambio).
      const saved = workRepoMock.save.mock.calls[0][0];
      expect(saved.propietario).toMatchObject({ id: 'prop-2' });
      expect(saved.propietarioId).toBe('prop-2');
    });

    it('re-vincula al propietario por ID verificando su existencia', async () => {
      const nuevo = { id: 'prop-3', email: 'otro@gmail.com', role: 'Propietario' };
      workRepoMock.findOne.mockResolvedValueOnce({ ...obra });
      userRepoMock.findOne.mockResolvedValueOnce(nuevo);
      workRepoMock.save.mockImplementation((w) => Promise.resolve(w));

      const result = await service.update('w1', { propietarioId: 'prop-3' } as never);

      expect(userRepoMock.findOne).toHaveBeenCalledWith({ where: { id: 'prop-3' } });
      expect(result.propietarioId).toBe('prop-3');
    });

    it('rechaza el cambio si el nuevo propietario no existe (CU-14 Alt. 2.1)', async () => {
      workRepoMock.findOne.mockResolvedValueOnce({ ...obra });
      userRepoMock.findOne.mockResolvedValueOnce(null);

      await expect(
        service.update('w1', { propietarioEmail: 'fantasma@gmail.com' } as never),
      ).rejects.toThrow(BadRequestException);
      expect(workRepoMock.save).not.toHaveBeenCalled();
    });

    it('no toca la vinculación si no se informa propietario', async () => {
      workRepoMock.findOne.mockResolvedValueOnce({ ...obra });
      workRepoMock.save.mockImplementation((w) => Promise.resolve(w));

      const result = await service.update('w1', { nombre: 'Edificio Norte' });

      expect(userRepoMock.findOne).not.toHaveBeenCalled();
      expect(result.propietarioId).toBe('prop-1');
      expect(result.nombre).toBe('Edificio Norte');
    });
  });

  describe('update - precondición "obra no archivada" (CU-17 / CU-21)', () => {
    const obraActiva = {
      id: 'w1',
      nombre: 'Edificio Central',
      estado: WorkStatus.PLANIFICATION,
      propietarioId: 'prop-1',
      deletedAt: null,
    };

    it('actualiza y refresca una obra en curso (Flujo Normal)', async () => {
      workRepoMock.findOne.mockResolvedValueOnce({ ...obraActiva });
      workRepoMock.save.mockImplementation((w) => Promise.resolve(w));

      const result = await service.update('w1', { nombre: 'Edificio Norte', direccion: 'Otra 123' });

      expect(workRepoMock.save).toHaveBeenCalled();
      expect(result.nombre).toBe('Edificio Norte');
      expect(result.direccion).toBe('Otra 123');
    });

    it('bloquea la edición de una obra con borrado lógico (400 claro)', async () => {
      workRepoMock.findOne.mockResolvedValueOnce({
        ...obraActiva,
        estado: WorkStatus.ARCHIVED,
        deletedAt: new Date('2026-08-01T00:00:00.000Z'),
      });

      await expect(service.update('w1', { nombre: 'Cambio' })).rejects.toThrow(
        new BadRequestException(
          'No se puede modificar una obra archivada. La obra permanece inalterable en el historial (CU-21).',
        ),
      );
      expect(workRepoMock.save).not.toHaveBeenCalled();
    });

    it('bloquea la edición si el estado es Archivado aunque no haya marca de borrado', async () => {
      workRepoMock.findOne.mockResolvedValueOnce({
        ...obraActiva,
        estado: WorkStatus.ARCHIVED,
        deletedAt: null,
      });

      await expect(service.update('w1', { nombre: 'Cambio' })).rejects.toThrow(BadRequestException);
      expect(workRepoMock.save).not.toHaveBeenCalled();
    });
  });

  describe('findOne (CU-19 Visualizar Ficha Técnica)', () => {
    const obra = {
      id: 'w1',
      nombre: 'Edificio Central',
      direccion: 'Av. Libertador 1234',
      estado: WorkStatus.PLANIFICATION,
      propietarioId: 'prop-1',
    };

    it('recupera la obra con su propietario vinculado', async () => {
      workRepoMock.findOne.mockResolvedValueOnce(obra);

      const result = await service.findOne('w1');

      expect(workRepoMock.findOne).toHaveBeenCalledWith({
        where: { id: 'w1' },
        relations: { propietario: true },
        withDeleted: true,
      });
      expect(result).toBe(obra);
    });

    it('lanza NotFound si la obra no existe', async () => {
      workRepoMock.findOne.mockResolvedValueOnce(null);

      await expect(service.findOne('inexistente')).rejects.toThrow(
        'La obra con ID inexistente no fue encontrada.',
      );
    });
  });

  describe('updateStatus (CU-20 Actualizar Estado del Proyecto)', () => {
    const obraEnPlanificacion = {
      id: 'w1',
      nombre: 'Edificio Central',
      estado: WorkStatus.PLANIFICATION,
      propietarioId: 'prop-1',
      deletedAt: null,
    };

    it('cambia la fase global de la obra (Flujo Normal)', async () => {
      workRepoMock.findOne.mockResolvedValueOnce({ ...obraEnPlanificacion });
      workRepoMock.save.mockImplementation((w) => Promise.resolve(w));

      const result = await service.updateStatus('w1', WorkStatus.IN_PROGRESS);

      expect(result.estado).toBe(WorkStatus.IN_PROGRESS);
      expect(workRepoMock.save).toHaveBeenCalledWith(
        expect.objectContaining({ id: 'w1', estado: WorkStatus.IN_PROGRESS }),
      );
    });

    it('rechaza un estado fuera del enum (defensa en profundidad)', async () => {
      await expect(
        service.updateStatus('w1', 'En Otro Lado' as WorkStatus),
      ).rejects.toThrow(new BadRequestException('Estado de obra inválido.'));
      expect(workRepoMock.findOne).not.toHaveBeenCalled();
      expect(workRepoMock.save).not.toHaveBeenCalled();
    });

    it('bloquea el cambio de estado de una obra archivada', async () => {
      workRepoMock.findOne.mockResolvedValueOnce({
        ...obraEnPlanificacion,
        estado: WorkStatus.ARCHIVED,
        deletedAt: new Date('2026-08-01T00:00:00.000Z'),
      });

      await expect(service.updateStatus('w1', WorkStatus.IN_PROGRESS)).rejects.toThrow(
        BadRequestException,
      );
      expect(workRepoMock.save).not.toHaveBeenCalled();
    });

    it('deriva el archivado a CU-21 en lugar de aplicarlo directo', async () => {
      workRepoMock.findOne.mockResolvedValueOnce({ ...obraEnPlanificacion });

      await expect(service.updateStatus('w1', WorkStatus.ARCHIVED)).rejects.toThrow(
        new BadRequestException(
          'El archivado de una obra se realiza con CU-21 (DELETE /works/:id), que exige obra completada y sin hitos en ejecución.',
        ),
      );
      expect(workRepoMock.save).not.toHaveBeenCalled();
    });
  });

  describe('archive (CU-21 Archivar Obra)', () => {
    const obraCompletada = {
      id: 'w1',
      nombre: 'Edificio Central',
      estado: WorkStatus.COMPLETED,
      propietarioId: 'prop-1',
      deletedAt: null,
    };

    it('archiva una obra completada: estado + borrado lógico (Flujo Normal)', async () => {
      workRepoMock.findOne.mockResolvedValueOnce({ ...obraCompletada });
      workRepoMock.save.mockImplementation((w) => Promise.resolve(w));
      workRepoMock.softDelete.mockResolvedValue({ affected: 1 });

      await service.archive('w1');

      expect(workRepoMock.save).toHaveBeenCalledWith(
        expect.objectContaining({ id: 'w1', estado: WorkStatus.ARCHIVED }),
      );
      expect(workRepoMock.softDelete).toHaveBeenCalledWith('w1');
    });

    it('bloquea el archivado de una obra no completada (Precondición)', async () => {
      workRepoMock.findOne.mockResolvedValueOnce({
        ...obraCompletada,
        estado: WorkStatus.IN_PROGRESS,
      });

      await expect(service.archive('w1')).rejects.toThrow(
        new BadRequestException(
          `Solo se puede archivar una obra en estado '${WorkStatus.COMPLETED}'. Estado actual: '${WorkStatus.IN_PROGRESS}'.`,
        ),
      );
      expect(workRepoMock.save).not.toHaveBeenCalled();
      expect(workRepoMock.softDelete).not.toHaveBeenCalled();
    });

    it('rechaza archivar dos veces (obra ya inalterable en el historial)', async () => {
      workRepoMock.findOne.mockResolvedValueOnce({
        ...obraCompletada,
        estado: WorkStatus.ARCHIVED,
        deletedAt: new Date('2026-08-01T00:00:00.000Z'),
      });

      await expect(service.archive('w1')).rejects.toThrow(
        new BadRequestException('La obra ya se encuentra archivada en el historial.'),
      );
      expect(workRepoMock.save).not.toHaveBeenCalled();
      expect(workRepoMock.softDelete).not.toHaveBeenCalled();
    });

    it('lanza NotFound si la obra no existe', async () => {
      workRepoMock.findOne.mockResolvedValueOnce(null);

      await expect(service.archive('inexistente')).rejects.toThrow(
        'La obra con ID inexistente no fue encontrada.',
      );
    });
  });
});