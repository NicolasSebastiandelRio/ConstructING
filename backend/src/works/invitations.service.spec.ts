import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import {
  NotFoundException,
  ConflictException,
  BadRequestException,
  GoneException,
} from '@nestjs/common';
import { InvitationsService } from './invitations.service';
import { WorkEntity, WorkStatus } from './entities/work.entity';
import { WorkInvitationEntity } from './entities/work-invitation.entity';
import { UserEntity } from '../auth/user.entity';
import { MailRetryQueueService } from '../auth/mail-retry-queue.service';

describe('InvitationsService - CU-22 (Generar Código de Invitación)', () => {
  let service: InvitationsService;

  const invitationRepoMock = {
    findOne: jest.fn(),
    create: jest.fn(),
    save: jest.fn(),
  };
  const workRepoMock = {
    findOne: jest.fn(),
    update: jest.fn(),
  };
  const userRepoMock = {
    findOne: jest.fn(),
  };
  const mailRetryQueueMock = {
    sendWithRetry: jest.fn().mockResolvedValue(undefined),
  };

  const obra = {
    id: 'w1',
    nombre: 'Edificio Central',
    estado: WorkStatus.IN_PROGRESS,
    deletedAt: null,
  };

  beforeEach(async () => {
    jest.clearAllMocks();
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        InvitationsService,
        { provide: getRepositoryToken(WorkInvitationEntity), useValue: invitationRepoMock },
        { provide: getRepositoryToken(WorkEntity), useValue: workRepoMock },
        { provide: getRepositoryToken(UserEntity), useValue: userRepoMock },
        { provide: MailRetryQueueService, useValue: mailRetryQueueMock },
      ],
    }).compile();

    service = module.get<InvitationsService>(InvitationsService);
  });

  it('debería estar definido', () => {
    expect(service).toBeDefined();
  });

  describe('create (pasos 1-2)', () => {
    it('genera un código único temporal y envía el correo (paso 4)', async () => {
      workRepoMock.findOne.mockResolvedValueOnce(obra);
      userRepoMock.findOne.mockResolvedValueOnce(null); // correo no registrado
      invitationRepoMock.findOne
        .mockResolvedValueOnce(null) // pendiente previa
        .mockResolvedValueOnce(null); // colisión de código
      invitationRepoMock.create.mockImplementation((data) => ({ id: 'i1', ...data }));
      invitationRepoMock.save.mockImplementation((i) => Promise.resolve(i));

      const result = await service.create('w1', 'nuevo@gmail.com');

      expect(result.code).toMatch(/^CNG-[A-Z2-9]{6}$/);
      expect(result.email).toBe('nuevo@gmail.com');
      expect(result.expiresAt.getTime()).toBeGreaterThan(Date.now());
      // Pendiente = sin fecha de uso (ausente en memoria, NULL en BD/JSON).
      expect(result.usedAt).toBeFalsy();
      expect(mailRetryQueueMock.sendWithRetry).toHaveBeenCalledWith(
        expect.objectContaining({ to: 'nuevo@gmail.com' }),
      );
      const mailText = mailRetryQueueMock.sendWithRetry.mock.calls[0][0].text as string;
      expect(mailText).toContain(result.code);
      expect(mailText).toContain('Edificio Central');
    });

    it('normaliza el correo a minúsculas', async () => {
      workRepoMock.findOne.mockResolvedValueOnce(obra);
      userRepoMock.findOne.mockResolvedValueOnce(null);
      invitationRepoMock.findOne.mockResolvedValue(null);
      invitationRepoMock.create.mockImplementation((data) => ({ id: 'i2', ...data }));
      invitationRepoMock.save.mockImplementation((i) => Promise.resolve(i));

      const result = await service.create('w1', 'Nuevo@Gmail.COM');

      expect(result.email).toBe('nuevo@gmail.com');
      expect(userRepoMock.findOne).toHaveBeenCalledWith({ where: { email: 'nuevo@gmail.com' } });
    });

    it('reutiliza una invitación pendiente y vigente (no duplica)', async () => {
      const pending = {
        id: 'i9',
        code: 'CNG-AAAAAA',
        workId: 'w1',
        email: 'nuevo@gmail.com',
        expiresAt: new Date(Date.now() + 86400000),
        usedAt: null,
      };
      workRepoMock.findOne.mockResolvedValueOnce(obra);
      userRepoMock.findOne.mockResolvedValueOnce(null);
      invitationRepoMock.findOne.mockResolvedValueOnce(pending);

      const result = await service.create('w1', 'nuevo@gmail.com');

      expect(result).toBe(pending);
      expect(invitationRepoMock.save).not.toHaveBeenCalled();
      expect(mailRetryQueueMock.sendWithRetry).not.toHaveBeenCalled();
    });

    it('falla 404 si la obra no existe', async () => {
      workRepoMock.findOne.mockResolvedValueOnce(null);

      await expect(service.create('inexistente', 'nuevo@gmail.com')).rejects.toThrow(
        NotFoundException,
      );
    });

    it('rechaza si el correo ya está registrado (CU-14 vincula directo)', async () => {
      workRepoMock.findOne.mockResolvedValueOnce(obra);
      userRepoMock.findOne.mockResolvedValueOnce({ id: 'u1', email: 'reg@gmail.com' });

      await expect(service.create('w1', 'reg@gmail.com')).rejects.toThrow(
        new ConflictException(
          'El correo ya se encuentra registrado. Vincule al propietario directamente con su correo (CU-14).',
        ),
      );
      expect(invitationRepoMock.save).not.toHaveBeenCalled();
    });

    it('rechaza invitar a una obra archivada', async () => {
      workRepoMock.findOne.mockResolvedValueOnce({ ...obra, estado: WorkStatus.ARCHIVED });

      await expect(service.create('w1', 'nuevo@gmail.com')).rejects.toThrow(BadRequestException);
    });
  });

  describe('resolve (consulta previa al registro)', () => {
    it('devuelve la invitación pendiente y vigente', async () => {
      const pending = { code: 'CNG-AAAAAA', usedAt: null, expiresAt: new Date(Date.now() + 86400000) };
      invitationRepoMock.findOne.mockResolvedValueOnce(pending);

      expect(await service.resolve('CNG-AAAAAA')).toBe(pending);
    });

    it('falla 404 si el código no existe', async () => {
      invitationRepoMock.findOne.mockResolvedValueOnce(null);

      await expect(service.resolve('CNG-XXXXXX')).rejects.toThrow(NotFoundException);
    });

    it('rechaza códigos ya usados o expirados (410 Gone)', async () => {
      invitationRepoMock.findOne.mockResolvedValueOnce({
        code: 'CNG-USED',
        usedAt: new Date(),
        expiresAt: new Date(Date.now() + 86400000),
      });
      await expect(service.resolve('CNG-USED')).rejects.toThrow(GoneException);

      invitationRepoMock.findOne.mockResolvedValueOnce({
        code: 'CNG-OLD',
        usedAt: null,
        expiresAt: new Date(Date.now() - 1000),
      });
      await expect(service.resolve('CNG-OLD')).rejects.toThrow(GoneException);
    });
  });

  describe('claim (reclamo en el registro CU-06/CU-22)', () => {
    const validInvitation = () => ({
      code: 'CNG-AAAAAA',
      workId: 'w1',
      email: 'nuevo@gmail.com',
      expiresAt: new Date(Date.now() + 86400000),
      usedAt: null,
    });

    it('marca como usada y vincula al nuevo usuario como propietario', async () => {
      const invitation = validInvitation();
      invitationRepoMock.findOne.mockResolvedValueOnce(invitation);
      workRepoMock.findOne.mockResolvedValueOnce(obra);
      invitationRepoMock.save.mockImplementation((i) => Promise.resolve(i));

      await service.claim('CNG-AAAAAA', 'nuevo@gmail.com', 'user-nuevo');

      expect(invitation.usedAt).not.toBeNull();
      expect(workRepoMock.update).toHaveBeenCalledWith('w1', { propietarioId: 'user-nuevo' });
    });

    it('rechaza si el correo no coincide con el invitado', async () => {
      invitationRepoMock.findOne.mockResolvedValueOnce(validInvitation());

      await expect(service.claim('CNG-AAAAAA', 'otro@gmail.com', 'u2')).rejects.toThrow(
        new BadRequestException('El código de invitación no corresponde a este correo.'),
      );
      expect(workRepoMock.update).not.toHaveBeenCalled();
    });

    it('rechaza códigos usados o expirados', async () => {
      invitationRepoMock.findOne.mockResolvedValueOnce({ ...validInvitation(), usedAt: new Date() });
      await expect(service.claim('CNG-AAAAAA', 'nuevo@gmail.com', 'u2')).rejects.toThrow(
        GoneException,
      );

      invitationRepoMock.findOne.mockResolvedValueOnce({
        ...validInvitation(),
        expiresAt: new Date(Date.now() - 1000),
      });
      await expect(service.claim('CNG-AAAAAA', 'nuevo@gmail.com', 'u2')).rejects.toThrow(
        GoneException,
      );
      expect(workRepoMock.update).not.toHaveBeenCalled();
    });

    it('rechaza si la obra ya no admite vinculaciones', async () => {
      invitationRepoMock.findOne.mockResolvedValueOnce(validInvitation());
      workRepoMock.findOne.mockResolvedValueOnce(null);

      await expect(service.claim('CNG-AAAAAA', 'nuevo@gmail.com', 'u2')).rejects.toThrow(
        new BadRequestException('La obra de la invitación ya no admite vinculaciones.'),
      );
    });
  });
});