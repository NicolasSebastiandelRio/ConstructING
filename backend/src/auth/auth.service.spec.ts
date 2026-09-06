import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { JwtService } from '@nestjs/jwt';
import { MailerService } from '@nestjs-modules/mailer';
import { ConflictException, BadRequestException } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';
import { UserEntity } from './user.entity';
import { WorkEntity } from '../works/entities/work.entity';
import { WorkInvitationEntity } from '../works/entities/work-invitation.entity';
import { MailRetryQueueService } from './mail-retry-queue.service';

describe('AuthService - CU-06 (Crear perfil de usuario)', () => {
  let service: AuthService;

  const mailerServiceMock = { sendMail: jest.fn().mockResolvedValue(true) };
  const jwtServiceMock = { sign: jest.fn().mockReturnValue('jwt-fake') };
  const mailRetryQueueMock = {
    sendWithRetry: jest.fn().mockResolvedValue(undefined),
  };

  const userRepoMock = {
    findOne: jest.fn(),
    create: jest.fn(),
    save: jest.fn(),
  };
  const invitationRepoMock = {
    findOne: jest.fn(),
    save: jest.fn(),
  };
  const workRepoMock = {
    findOne: jest.fn(),
    update: jest.fn(),
  };

  beforeEach(async () => {
    jest.clearAllMocks();
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        { provide: getRepositoryToken(UserEntity), useValue: userRepoMock },
        { provide: getRepositoryToken(WorkInvitationEntity), useValue: invitationRepoMock },
        { provide: getRepositoryToken(WorkEntity), useValue: workRepoMock },
        { provide: JwtService, useValue: jwtServiceMock },
        { provide: MailerService, useValue: mailerServiceMock },
        { provide: MailRetryQueueService, useValue: mailRetryQueueMock },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
  });

  describe('Registro exitoso', () => {
    it('persiste el usuario con nombre, rol y password hasheado (bcrypt)', async () => {
      userRepoMock.findOne.mockResolvedValue(null);
      userRepoMock.create.mockImplementation((data) => ({
        id: 'uuid-1',
        nombre: data.nombre,
        email: data.email,
        passwordHash: data.passwordHash,
        role: data.role,
      }));
      userRepoMock.save.mockImplementation((u) => Promise.resolve(u));

      const result = await service.register({
        nombre: 'Ana García',
        email: 'ana@gmail.com',
        password: 'secreta123',
        role: 'Propietario',
      });

      expect(userRepoMock.create).toHaveBeenCalledWith(
        expect.objectContaining({
          email: 'ana@gmail.com',
          role: 'Propietario',
          nombre: 'Ana García',
          passwordHash: expect.any(String),
        }),
      );
      // CU-11: la contraseña debe guardarse encriptada (bcrypt), nunca en claro.
      const savedPasswordHash = userRepoMock.create.mock.calls[0][0].passwordHash;
      expect(savedPasswordHash).not.toBe('secreta123');
      expect(await bcrypt.compare('secreta123', savedPasswordHash)).toBe(true);

      expect(result).toEqual(
        expect.objectContaining({ id: 'uuid-1', nombre: 'Ana García', email: 'ana@gmail.com', rol: 'Propietario' }),
      );
      expect(userRepoMock.save).toHaveBeenCalledTimes(1);
    });

    it('encola el correo de bienvenida tras guardar (CU-12)', async () => {
      userRepoMock.findOne.mockResolvedValue(null);
      userRepoMock.create.mockImplementation((data) => ({
        id: 'uuid-2',
        nombre: data.nombre,
        email: data.email,
        passwordHash: data.passwordHash,
        role: data.role,
      }));
      userRepoMock.save.mockImplementation((u) => Promise.resolve(u));

      await service.register({
        nombre: 'Luis',
        email: 'luis@gmail.com',
        password: 'claveSegura1',
        role: 'Profesional',
      });

      expect(mailRetryQueueMock.sendWithRetry).toHaveBeenCalledWith(
        expect.objectContaining({ to: 'luis@gmail.com' }),
      );
    });
  });

  describe('CU-10 - Validar unicidad de identidad', () => {
    it('rechaza el registro si el correo ya existe (mensaje de la spec)', async () => {
      userRepoMock.findOne.mockResolvedValue({ id: 'x', email: 'dupe@gmail.com' });

      await expect(
        service.register({
          nombre: 'Otro',
          email: 'dupe@gmail.com',
          password: 'claveSegura1',
          role: 'Propietario',
        }),
      ).rejects.toThrow(
        new ConflictException('El correo ya se encuentra en uso. Por favor, inicie sesión'),
      );
    });

    it('respaldado por la BD: convierte la violación UNIQUE en el mensaje de la spec', async () => {
      userRepoMock.findOne.mockResolvedValue(null);
      const conflict = new (require('typeorm').QueryFailedError)(
        'INSERT',
        [],
        { code: '23505' },
      );
      userRepoMock.save.mockRejectedValue(conflict);

      await expect(
        service.register({
          nombre: 'Racer',
          email: 'tomado@gmail.com',
          password: 'claveSegura1',
          role: 'Propietario',
        }),
      ).rejects.toThrow(
        new ConflictException('El correo ya se encuentra en uso. Por favor, inicie sesión'),
      );
    });
  });

  describe('RNF_S_01 - Política de complejidad de contraseña', () => {
    it('rechaza contraseñas con menos de 8 caracteres', async () => {
      await expect(
        service.register({ email: 'a@b.com', password: 'short1', role: 'Propietario' }),
      ).rejects.toThrow(new BadRequestException('La contraseña debe tener al menos 8 caracteres y un número'));
      expect(userRepoMock.save).not.toHaveBeenCalled();
    });

    it('rechaza contraseñas de 8 caracteres sin número', async () => {
      await expect(
        service.register({ email: 'a@b.com', password: 'abcdefgh', role: 'Propietario' }),
      ).rejects.toThrow(new BadRequestException('La contraseña debe tener al menos 8 caracteres y un número'));
      expect(userRepoMock.save).not.toHaveBeenCalled();
    });

    it('acepta una contraseña de 8 caracteres con número', async () => {
      userRepoMock.findOne.mockResolvedValue(null);
      userRepoMock.create.mockImplementation((data) => ({ ...data, id: 'u' }));
      userRepoMock.save.mockImplementation((u) => Promise.resolve(u));

      await expect(
        service.register({ email: 'a@b.com', password: 'secreto1', role: 'Propietario' }),
      ).resolves.toBeDefined();
    });
  });

  describe('CU-11 + CU-03 - Encriptar credenciales', () => {    it('hashea la nueva contraseña en el reset y purga el código de recuperación', async () => {
      userRepoMock.findOne.mockResolvedValue({ id: 'u', email: 'a@b.com', recoveryCode: '123456' });
      userRepoMock.save.mockImplementation((u) => Promise.resolve(u));

      await service.resetPassword({ email: 'a@b.com', code: '123456', newPassword: 'nuevaClave1' });

      const saved = userRepoMock.save.mock.calls[0][0];
      expect(saved.passwordHash).not.toBe('nuevaClave1');
      expect(await bcrypt.compare('nuevaClave1', saved.passwordHash)).toBe(true);
      expect(saved.recoveryCode).toBeNull();
    });

    it('rechaza un nuevo password que no cumple la política (RNF_S_01)', async () => {
      userRepoMock.findOne.mockResolvedValueOnce({ id: 'u', email: 'a@b.com', recoveryCode: '123456' });

      await expect(
        service.resetPassword({ email: 'a@b.com', code: '123456', newPassword: 'corto' }),
      ).rejects.toThrow(new BadRequestException('La contraseña debe tener al menos 8 caracteres y un número'));
      expect(userRepoMock.save).not.toHaveBeenCalled();
    });
  });

  describe('CU-22 - Reclamo de invitación en el registro (CU-06)', () => {
    const invitation = () => ({
      code: 'CNG-AAAAAA',
      workId: 'w1',
      email: 'invitado@gmail.com',
      expiresAt: new Date(Date.now() + 86400000),
      usedAt: null,
    });

    it('vincula al nuevo usuario como propietario y marca el código como usado', async () => {
      userRepoMock.findOne.mockResolvedValueOnce(null); // unicidad CU-10
      invitationRepoMock.findOne.mockResolvedValueOnce(invitation());
      userRepoMock.create.mockImplementation((data) => ({ id: 'user-nuevo', ...data }));
      userRepoMock.save.mockImplementation((u) => Promise.resolve(u));
      workRepoMock.findOne.mockResolvedValueOnce({ id: 'w1', estado: 'En Ejecución', deletedAt: null });
      invitationRepoMock.save.mockImplementation((i) => Promise.resolve(i));

      await service.register({
        nombre: 'Invitado',
        email: 'invitado@gmail.com',
        password: 'claveSegura1',
        role: 'Propietario',
        invitationCode: 'CNG-AAAAAA',
      });

      expect(workRepoMock.update).toHaveBeenCalledWith('w1', { propietarioId: 'user-nuevo' });
    });

    it('rechaza el registro si el código no existe (sin persistir)', async () => {
      userRepoMock.findOne.mockResolvedValueOnce(null);
      invitationRepoMock.findOne.mockResolvedValueOnce(null);

      await expect(
        service.register({
          email: 'invitado@gmail.com',
          password: 'claveSegura1',
          role: 'Propietario',
          invitationCode: 'CNG-XXXXXX',
        }),
      ).rejects.toThrow('El código de invitación no existe.');
      expect(userRepoMock.save).not.toHaveBeenCalled();
    });

    it('rechaza si el código no corresponde al correo (sin persistir)', async () => {
      userRepoMock.findOne.mockResolvedValueOnce(null);
      invitationRepoMock.findOne.mockResolvedValueOnce(invitation());

      await expect(
        service.register({
          email: 'otro@gmail.com',
          password: 'claveSegura1',
          role: 'Propietario',
          invitationCode: 'CNG-AAAAAA',
        }),
      ).rejects.toThrow('El código de invitación no corresponde a este correo.');
      expect(userRepoMock.save).not.toHaveBeenCalled();
    });
  });
});