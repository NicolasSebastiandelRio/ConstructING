import { Test, TestingModule } from '@nestjs/testing';
import { WorksController } from './works.controller';
import { WorksService } from './works.service';
import { InvitationsService } from './invitations.service';
import { WorkStatus } from './entities/work.entity';

describe('WorksController - CU-13 (Crear Nueva Obra)', () => {
  let controller: WorksController;
  let service: WorksService;

  const workFixture = {
    id: 'w1',
    nombre: 'Edificio Central',
    direccion: 'Av. Libertador 1234',
    fechaInicio: '2026-09-01',
    estado: WorkStatus.PLANIFICATION,
    propietarioId: 'prop-1',
  };

  const worksServiceMock = {
    create: jest.fn(),
    findAll: jest.fn(),
    findOne: jest.fn(),
    update: jest.fn(),
    updateStatus: jest.fn(),
    archive: jest.fn(),
  };

  const invitationsServiceMock = {
    create: jest.fn(),
    resolve: jest.fn(),
    claim: jest.fn(),
  };

  beforeEach(async () => {
    jest.clearAllMocks();
    const module: TestingModule = await Test.createTestingModule({
      controllers: [WorksController],
      providers: [
        { provide: WorksService, useValue: worksServiceMock },
        { provide: InvitationsService, useValue: invitationsServiceMock },
      ],
    }).compile();

    controller = module.get<WorksController>(WorksController);
    service = module.get<WorksService>(WorksService);
  });

  it('debería estar definido', () => {
    expect(controller).toBeDefined();
  });

  it('POST /works delega en WorksService.create y devuelve la obra creada (201)', async () => {
    const dto = {
      nombre: 'Edificio Central',
      direccion: 'Av. Libertador 1234',
      fechaInicio: '2026-09-01',
      propietarioEmail: 'dueño@gmail.com',
    };
    worksServiceMock.create.mockResolvedValue(workFixture);

    const result = await controller.create(dto as never);

    expect(service.create).toHaveBeenCalledWith(dto);
    expect(result).toMatchObject({ id: 'w1', estado: WorkStatus.PLANIFICATION });
  });

  it('PATCH /works/:id delega en WorksService.update (CU-14 desde edición / CU-17)', async () => {
    const dto = { propietarioEmail: 'nuevo@gmail.com' };
    worksServiceMock.update.mockResolvedValue({ ...workFixture, propietarioId: 'prop-2' });

    const result = await controller.update('w1', dto as never);

    expect(service.update).toHaveBeenCalledWith('w1', dto);
    expect(result).toMatchObject({ propietarioId: 'prop-2' });
  });

  it('GET /works sin filtro pide el listado general (CU-18 Profesional)', async () => {
    worksServiceMock.findAll.mockResolvedValue([workFixture]);

    const result = await controller.findAll();

    expect(service.findAll).toHaveBeenCalledWith(undefined, false);
    expect(result).toHaveLength(1);
  });

  it('GET /works?propietarioId= pide "Mis Obras" del propietario (CU-18)', async () => {
    worksServiceMock.findAll.mockResolvedValue([workFixture]);

    await controller.findAll('prop-1');

    expect(service.findAll).toHaveBeenCalledWith('prop-1', false);
  });

  it('GET /works?archived=true pide el historial de archivadas (CU-21)', async () => {
    worksServiceMock.findAll.mockResolvedValue([]);

    await controller.findAll(undefined, 'true');

    expect(service.findAll).toHaveBeenCalledWith(undefined, true);
  });

  it('GET /works/:id delega en WorksService.findOne (CU-19)', async () => {
    worksServiceMock.findOne.mockResolvedValue(workFixture);

    const result = await controller.findOne('w1');

    expect(service.findOne).toHaveBeenCalledWith('w1');
    expect(result).toMatchObject({ id: 'w1', nombre: 'Edificio Central' });
  });

  it('CU-19 (seguridad): nunca expone el passwordHash del propietario vinculado', async () => {
    const withOwner = {
      ...workFixture,
      propietario: {
        id: 'prop-1',
        nombre: 'Dueño López',
        email: 'dueño@gmail.com',
        passwordHash: 'hash-secreto',
      },
    };
    worksServiceMock.findOne.mockResolvedValue(withOwner);
    worksServiceMock.findAll.mockResolvedValue([withOwner]);

    const one = await controller.findOne('w1');
    const all = await controller.findAll();

    expect((one.propietario as Record<string, unknown>).passwordHash).toBeUndefined();
    expect((one.propietario as Record<string, unknown>).email).toBe('dueño@gmail.com');
    expect((all[0].propietario as Record<string, unknown>).passwordHash).toBeUndefined();
  });

  it('PATCH /works/:id/status delega con el DTO validado (CU-20)', async () => {
    worksServiceMock.updateStatus.mockResolvedValue({ ...workFixture, estado: WorkStatus.IN_PROGRESS });

    const result = await controller.updateStatus('w1', { estado: WorkStatus.IN_PROGRESS });

    expect(service.updateStatus).toHaveBeenCalledWith('w1', WorkStatus.IN_PROGRESS);
    expect(result).toMatchObject({ estado: WorkStatus.IN_PROGRESS });
  });

  it('POST /works/:id/invitations delega en InvitationsService.create (CU-22)', async () => {
    const invitation = { id: 'i1', code: 'CNG-AAAAAA', workId: 'w1', email: 'nuevo@gmail.com' };
    invitationsServiceMock.create.mockResolvedValue(invitation);

    const result = await controller.createInvitation('w1', { email: 'nuevo@gmail.com' });

    expect(invitationsServiceMock.create).toHaveBeenCalledWith('w1', 'nuevo@gmail.com');
    expect(result).toMatchObject({ code: 'CNG-AAAAAA' });
  });

  it('GET /works/invitations/:code delega en InvitationsService.resolve (CU-22)', async () => {
    const invitation = { code: 'CNG-AAAAAA', workId: 'w1', email: 'nuevo@gmail.com' };
    invitationsServiceMock.resolve.mockResolvedValue(invitation);

    const result = await controller.resolveInvitation('CNG-AAAAAA');

    expect(invitationsServiceMock.resolve).toHaveBeenCalledWith('CNG-AAAAAA');
    expect(result).toMatchObject({ workId: 'w1' });
  });
});