import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { BadRequestException, NotFoundException } from '@nestjs/common';
import { QueryFailedError } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { UsersService } from './users.service';
import { UserEntity } from '../auth/user.entity';

describe('UsersService - CU-07 (Modificar datos de usuario)', () => {
  let service: UsersService;

  const userRepoMock = {
    find: jest.fn(),
    findOne: jest.fn(),
    save: jest.fn(),
    softDelete: jest.fn(),
    restore: jest.fn(),
  };

  const activeUser = {
    id: 'u1',
    nombre: 'Ana García',
    email: 'ana@gmail.com',
    role: 'Propietario',
    passwordHash: 'hash-viejo',
  };

  beforeEach(async () => {
    jest.clearAllMocks();
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        UsersService,
        { provide: getRepositoryToken(UserEntity), useValue: userRepoMock },
      ],
    }).compile();

    service = module.get<UsersService>(UsersService);
  });

  it('debería estar definido', () => {
    expect(service).toBeDefined();
  });

  describe('update (CU-07 Flujo Normal)', () => {
    it('actualiza nombre y email precargados y devuelve el perfil sin hash', async () => {
      userRepoMock.findOne
        .mockResolvedValueOnce(activeUser) // findOne del usuario a editar
        .mockResolvedValueOnce(null); // consulta de unicidad de email
      userRepoMock.save.mockImplementation((u) => Promise.resolve({ ...u }));

      const result = await service.update('u1', { nombre: 'Ana Pérez', email: 'nuevo@gmail.com' });

      expect(userRepoMock.save).toHaveBeenCalledWith(
        expect.objectContaining({ nombre: 'Ana Pérez', email: 'nuevo@gmail.com' }),
      );
      expect(result.passwordHash).toBeUndefined();
    });

    it('mantiene el email original sin consultar unicidad si no cambia (CU-10)', async () => {
      userRepoMock.findOne.mockResolvedValueOnce(activeUser);
      userRepoMock.save.mockImplementation((u) => Promise.resolve({ ...u }));

      await service.update('u1', { nombre: 'Ana García' });

      expect(userRepoMock.findOne).toHaveBeenCalledTimes(1); // solo para encontrar el usuario
    });

    it('lanza NotFound si el usuario no existe', async () => {
      userRepoMock.findOne.mockResolvedValue(null);

      await expect(service.update('inexistente', { nombre: 'X' })).rejects.toThrow(
        NotFoundException,
      );
      expect(userRepoMock.save).not.toHaveBeenCalled();
    });
  });

  describe('update - Flujo Alterno 3.1/3.2 (correo duplicado)', () => {
    it('detiene la operación con el mensaje "Correo ya registrado"', async () => {
      userRepoMock.findOne
        .mockResolvedValueOnce(activeUser)
        .mockResolvedValueOnce({ id: 'otra', email: 'tomado@gmail.com' }); // el correo ya es de otro

      await expect(
        service.update('u1', { email: 'tomado@gmail.com' }),
      ).rejects.toThrow(new BadRequestException('Correo ya registrado'));
      expect(userRepoMock.save).not.toHaveBeenCalled();
    });

    it('respaldado por la BD: convierte la violación UNIQUE en "Correo ya registrado"', async () => {
      userRepoMock.findOne.mockResolvedValueOnce(activeUser); // usuario a editar, sin cambio de correo
      const conflict = new QueryFailedError('', [] as never, {
        code: 'SQLITE_CONSTRAINT_UNIQUE',
      } as never);
      userRepoMock.save.mockRejectedValueOnce(conflict);

      await expect(service.update('u1', { email: 'dupe@gmail.com' })).rejects.toThrow(
        new BadRequestException('Correo ya registrado'),
      );
    });
  });

  describe('update + CU-11 (Encriptar credenciales)', () => {
    it('hashea la contraseña antes de persistir si se modifica', async () => {
      userRepoMock.findOne.mockResolvedValueOnce(activeUser);
      userRepoMock.save.mockImplementation((u) => Promise.resolve({ ...u }));

      await service.update('u1', { password: 'nuevaClave1' });

      const saved = userRepoMock.save.mock.calls[0][0];
      expect(saved.passwordHash).not.toBe('nuevaClave1');
      expect(await bcrypt.compare('nuevaClave1', saved.passwordHash)).toBe(true);
    });

    it('rechaza una contraseña que no cumple la política (RNF_S_01)', async () => {
      userRepoMock.findOne.mockResolvedValueOnce(activeUser);

      await expect(service.update('u1', { password: 'corta' })).rejects.toThrow(
        new BadRequestException('La contraseña debe tener al menos 8 caracteres y un número'),
      );
      expect(userRepoMock.save).not.toHaveBeenCalled();
    });
  });

  describe('softDelete / restore (CU-08 + RNF_S_03)', () => {
    it('aplica borrado lógico buscando primero al usuario existente', async () => {
      userRepoMock.findOne.mockResolvedValueOnce(activeUser);
      userRepoMock.softDelete.mockResolvedValue({ affected: 1 });

      await service.softDelete('u1');

      expect(userRepoMock.findOne).toHaveBeenCalledWith({
        where: { id: 'u1' },
        withDeleted: true,
      });
      expect(userRepoMock.softDelete).toHaveBeenCalledWith('u1');
    });

    it('falla con NotFound si el usuario no existe (no toca la BD)', async () => {
      userRepoMock.findOne.mockResolvedValueOnce(null);

      await expect(service.softDelete('inexistente')).rejects.toThrow(NotFoundException);
      expect(userRepoMock.softDelete).not.toHaveBeenCalled();
    });

    it('restore limpia la marca de borrado lógico del usuario inhabilitado', async () => {
      const inactive = { ...activeUser, deletedAt: new Date('2026-08-01T00:00:00.000Z') };
      userRepoMock.findOne.mockResolvedValueOnce(inactive);
      userRepoMock.restore.mockResolvedValue({ affected: 1 });

      const result = await service.restore('u1');

      expect(userRepoMock.restore).toHaveBeenCalledWith('u1');
      expect(result.deletedAt).toBeNull();
    });
  });

  describe('findAll (CU-09)', () => {
    it('consulta activos e inactivos incluyendo cuentas inhabilitadas', async () => {
      userRepoMock.find.mockResolvedValueOnce([activeUser]);

      await service.findAll();

      expect(userRepoMock.find).toHaveBeenCalledWith({ withDeleted: true });
    });
  });
});