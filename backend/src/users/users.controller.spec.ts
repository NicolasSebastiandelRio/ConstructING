import { Test, TestingModule } from '@nestjs/testing';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';

describe('UsersController - CU-07 (Modificar datos de usuario)', () => {
  let controller: UsersController;
  let service: UsersService;

  const userFixture = {
    id: 'u1',
    nombre: 'Ana García',
    email: 'ana@gmail.com',
    role: 'Propietario',
    passwordHash: 'hash-secreto',
    deletedAt: null,
  };

  const usersServiceMock = {
    findAll: jest.fn(),
    findOne: jest.fn(),
    update: jest.fn(),
    softDelete: jest.fn(),
    restore: jest.fn(),
  };

  beforeEach(async () => {
    jest.clearAllMocks();
    const module: TestingModule = await Test.createTestingModule({
      controllers: [UsersController],
      providers: [{ provide: UsersService, useValue: usersServiceMock }],
    }).compile();

    controller = module.get<UsersController>(UsersController);
    service = module.get<UsersService>(UsersService);
  });

  it('debería estar definido', () => {
    expect(controller).toBeDefined();
  });

  it('PATCH /users/:id delega en UsersService.update (CU-07)', async () => {
    const dto = { nombre: 'Ana Pérez', email: 'nuevo@gmail.com' };
    usersServiceMock.update.mockResolvedValue({ ...userFixture, ...dto });

    const result = await controller.update('u1', dto);

    expect(service.update).toHaveBeenCalledWith('u1', dto);
    expect(result).toMatchObject(dto);
  });

  it('la respuesta nunca expone el passwordHash (seguridad)', async () => {
    usersServiceMock.update.mockResolvedValue(userFixture);
    usersServiceMock.findOne.mockResolvedValue(userFixture);
    usersServiceMock.findAll.mockResolvedValue([userFixture]);
    usersServiceMock.restore.mockResolvedValue(userFixture);

    const updated = await controller.update('u1', { nombre: 'X' });
    const one = await controller.findOne('u1');
    const all = await controller.findAll();
    const restored = await controller.restore('u1');

    expect(updated).not.toHaveProperty('passwordHash');
    expect(one).not.toHaveProperty('passwordHash');
    expect(all).not.toHaveProperty('passwordHash');
    expect(restored).not.toHaveProperty('passwordHash');
  });

  it('DELETE /users/:id delega en UsersService.softDelete (CU-08)', async () => {
    usersServiceMock.softDelete.mockResolvedValue(undefined);

    await controller.remove('u1');

    expect(service.softDelete).toHaveBeenCalledWith('u1');
  });

  it('POST /users/:id/restore habilita y nunca expone el passwordHash (CU-08)', async () => {
    usersServiceMock.restore.mockResolvedValue({ ...userFixture, deletedAt: null });

    const result = await controller.restore('u1');

    expect(service.restore).toHaveBeenCalledWith('u1');
    expect(result).not.toHaveProperty('passwordHash');
    expect(result).toMatchObject({ id: 'u1', deletedAt: null });
  });
});