import {
  Injectable,
  NotFoundException,
  ConflictException,
  BadRequestException,
  GoneException,
  InternalServerErrorException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { WorkEntity, WorkStatus } from './entities/work.entity';
import { WorkInvitationEntity } from './entities/work-invitation.entity';
import { UserEntity } from '../auth/user.entity';
import { MailRetryQueueService } from '../auth/mail-retry-queue.service';
import {
  generateInvitationCode,
  normalizeInvitationEmail,
  assertInvitationClaimable,
  INVITATION_EXPIRY_DAYS,
} from './invitation-code';

const APP_DOWNLOAD_URL =
  process.env.APP_DOWNLOAD_URL ?? 'https://constructing.app/descargar';

@Injectable()
export class InvitationsService {
  constructor(
    @InjectRepository(WorkInvitationEntity)
    private readonly invitationRepository: Repository<WorkInvitationEntity>,
    @InjectRepository(WorkEntity)
    private readonly workRepository: Repository<WorkEntity>,
    @InjectRepository(UserEntity)
    private readonly userRepository: Repository<UserEntity>,
    private readonly mailRetryQueue: MailRetryQueueService,
  ) {}

  /**
   * CU-22 pasos 1-2: genera un código único temporal asociado a la obra.
   * Si el correo ya está registrado, se rechaza (ese caso lo resuelve CU-14
   * con vinculación directa, sin invitación).
   */
  async create(workId: string, email: string): Promise<WorkInvitationEntity> {
    const obra = await this.workRepository.findOne({ where: { id: workId } });
    if (!obra) {
      throw new NotFoundException(`La obra con ID ${workId} no fue encontrada.`);
    }
    if (obra.deletedAt || obra.estado === WorkStatus.ARCHIVED) {
      throw new BadRequestException('No se puede invitar a una obra archivada.');
    }

    const normalizedEmail = normalizeInvitationEmail(email);
    const registered = await this.userRepository.findOne({ where: { email: normalizedEmail } });
    if (registered) {
      // CU-14 Alt: el correo existe → vinculación directa, no invitación.
      throw new ConflictException(
        'El correo ya se encuentra registrado. Vincule al propietario directamente con su correo (CU-14).',
      );
    }

    // Reutiliza una invitación pendiente y vigente para el mismo correo y obra.
    const pending = await this.invitationRepository.findOne({
      where: { workId, email: normalizedEmail },
    });
    if (pending && !pending.usedAt && pending.expiresAt.getTime() > Date.now()) {
      return pending;
    }

    const invitation = this.invitationRepository.create({
      code: await this.generateUniqueCode(),
      workId,
      email: normalizedEmail,
      expiresAt: new Date(Date.now() + INVITATION_EXPIRY_DAYS * 24 * 60 * 60 * 1000),
    });
    const saved = await this.invitationRepository.save(invitation);

    // CU-22 paso 4: correo con el código y el enlace de descarga de la app.
    await this.mailRetryQueue.sendWithRetry({
      to: normalizedEmail,
      subject: 'Te invitaron a una obra en ConstructING',
      text:
        `Hola. Te invitaron como propietario de la obra "${obra.nombre}".\n` +
        `Tu código de invitación es: ${saved.code}\n` +
        `Descargá la app aquí: ${APP_DOWNLOAD_URL}\n` +
        `Ingresá el código al registrarte para unirte automáticamente a tu obra.`,
    });

    return saved;
  }

  /**
   * Resuelve un código para consulta previa al registro: valida existencia,
   * vigencia y uso pendiente (sin exigir el correo todavía). Los códigos
   * usados o expirados responden 410 Gone, igual que en el reclamo.
   */
  async resolve(code: string): Promise<WorkInvitationEntity> {
    const invitation = await this.invitationRepository.findOne({ where: { code } });
    if (!invitation) {
      throw new NotFoundException('El código de invitación no existe.');
    }
    if (invitation.usedAt) {
      throw new GoneException('El código de invitación ya fue utilizado.');
    }
    if (invitation.expiresAt.getTime() <= Date.now()) {
      throw new GoneException('El código de invitación expiró.');
    }
    return invitation;
  }

  /**
   * Reclamo en el registro (CU-06/CU-22 poscondición): valida el código
   * contra el correo del nuevo usuario, lo marca como usado y lo vincula
   * como propietario de la obra.
   */
  async claim(code: string, email: string, userId: string): Promise<WorkInvitationEntity> {
    const invitation = await this.invitationRepository.findOne({ where: { code } });
    assertInvitationClaimable(invitation, email);

    const obra = await this.workRepository.findOne({ where: { id: invitation.workId } });
    if (!obra || obra.deletedAt || obra.estado === WorkStatus.ARCHIVED) {
      throw new BadRequestException('La obra de la invitación ya no admite vinculaciones.');
    }

    invitation.usedAt = new Date();
    await this.invitationRepository.save(invitation);
    await this.workRepository.update(invitation.workId, { propietarioId: userId });
    return invitation;
  }

  private async generateUniqueCode(attempts = 5): Promise<string> {
    for (let i = 0; i < attempts; i++) {
      const code = generateInvitationCode();
      const exists = await this.invitationRepository.findOne({ where: { code } });
      if (!exists) return code;
    }
    throw new InternalServerErrorException('No se pudo generar un código de invitación único.');
  }
}
