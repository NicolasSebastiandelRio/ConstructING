import { Injectable, UnauthorizedException, ConflictException, BadRequestException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { UserEntity } from './user.entity';
import { WorkEntity, WorkStatus } from '../works/entities/work.entity';
import { WorkInvitationEntity } from '../works/entities/work-invitation.entity';
import { validatePasswordPolicy } from '../common/password-policy';
import { assertInvitationClaimable } from '../works/invitation-code';
import { MailRetryQueueService } from './mail-retry-queue.service';
import { isUniqueConstraintViolation } from '../common/db-error';

const SALT_ROUNDS = 10;

export interface RegisterDto {
  email: string;
  password: string;
  role?: string;
  rol?: string;
  nombre?: string;
  matricula?: string;
  /** CU-22: código de invitación a reclamar en el registro (opcional). */
  invitationCode?: string;
}

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(UserEntity)
    private readonly userRepository: Repository<UserEntity>,
    @InjectRepository(WorkInvitationEntity)
    private readonly invitationRepository: Repository<WorkInvitationEntity>,
    @InjectRepository(WorkEntity)
    private readonly workRepository: Repository<WorkEntity>,
    private readonly jwtService: JwtService,
    private readonly mailRetryQueue: MailRetryQueueService,
  ) {}

  /**
   * CU-06: Registro de nuevo usuario (Propietario o Profesional)
   */
  async register(dto: RegisterDto) {
    const userRole = dto.role || dto.rol || 'Propietario';

    // CU-06 Flujo Alterno 3.1/3.2: política de seguridad (RNF_S_01) validada
    // también en backend como defensa en profundidad.
    validatePasswordPolicy(dto.password);

    // CU-10: Validar unicidad de identidad
    const existingUser = await this.userRepository.findOne({ where: { email: dto.email } });
    
    // CU-06 Flujo Alterno 4.1/4.2: mensaje visual exacto de la especificación
    if (existingUser) {
      throw new ConflictException('El correo ya se encuentra en uso. Por favor, inicie sesión');
    }

    // CU-22 poscondición (pre-validación): si se informa un código, debe ser
    // válido ANTES de crear el usuario para no persistir cuentas huérfanas.
    let invitation: WorkInvitationEntity | null = null;
    if (dto.invitationCode) {
      invitation = await this.invitationRepository.findOne({
        where: { code: dto.invitationCode },
      });
      assertInvitationClaimable(invitation, dto.email);
    }

    // CU-11: Encriptar credenciales de acceso con bcrypt
    const hashedPassword = await bcrypt.hash(dto.password, SALT_ROUNDS);

    const nombre = dto.nombre?.trim() || '';
    const newUser = this.userRepository.create({
      email: dto.email,
      passwordHash: hashedPassword,
      role: userRole,
      nombre,
    });

    // CU-10: además del chequeo previo, la restricción UNIQUE de la columna
    // correo respalda la unicidad frente a condiciones de carrera (dos
    // registros simultáneos con el mismo correo no pueden persistir ambos).
    try {
      await this.userRepository.save(newUser);
    } catch (error) {
      if (isUniqueConstraintViolation(error)) {
        throw new ConflictException('El correo ya se encuentra en uso. Por favor, inicie sesión');
      }
      throw error;
    }

    // CU-12: correo de bienvenida automática con reintentos (Flujo Alt. 4.2)
    await this.mailRetryQueue.sendWithRetry({
      to: newUser.email,
      subject: '¡Bienvenido a ConstructING!',
      text: `Hola${nombre ? ' ' + nombre : ''}. Tu cuenta con el rol de ${newUser.role} ha sido creada exitosamente. Ya puedes ingresar al sistema.`,
    });

    // CU-22 poscondición (reclamo): el nuevo usuario queda vinculado como
    // propietario de la obra y el código se marca como usado.
    if (invitation) {
      const obra = await this.workRepository.findOne({ where: { id: invitation.workId } });
      if (!obra || obra.deletedAt || obra.estado === WorkStatus.ARCHIVED) {
        throw new BadRequestException('La obra de la invitación ya no admite vinculaciones.');
      }
      invitation.usedAt = new Date();
      await this.invitationRepository.save(invitation);
      await this.workRepository.update(invitation.workId, { propietarioId: newUser.id });
    }
    
    // Retornamos el objeto con el contrato exacto que UserModel.fromJson espera en el cliente
    return {
      id: newUser.id,
      nombre: nombre || 'Usuario ConstructING',
      email: newUser.email,
      rol: newUser.role,
      role: newUser.role,
      matricula: dto.matricula || null,
      message: 'Usuario registrado exitosamente',
    };
  }

  /**
   * CU-01: Autenticación de usuarios y generación de JWT (CU-05)
   */
  async login(dto: { email: string; password: string }) {
    const user = await this.userRepository.findOne({ where: { email: dto.email } });
    if (!user) {
      throw new UnauthorizedException('Credenciales inválidas.');
    }

    const isPasswordValid = await bcrypt.compare(dto.password, user.passwordHash);
    if (!isPasswordValid) {
      throw new UnauthorizedException('Credenciales inválidas.');
    }

    const payload = { sub: user.id, email: user.email, role: user.role };
    const access_token = this.jwtService.sign(payload);

    // Retornamos el token y la entidad 'user' que AuthRemoteDataSource e Iniciar Sesión exigen
    return {
      access_token,
      user: {
        id: user.id,
        nombre: user.nombre || 'Usuario ConstructING',
        email: user.email,
        rol: user.role,
        role: user.role,
        matricula: null,
      },
      role: user.role,
      message: 'Autenticación exitosa',
    };
  }

  /**
   * CU-03: Paso 1 - Enviar código temporal de recuperación
   */
  async forgotPassword(email: string) {
    const user = await this.userRepository.findOne({ where: { email } });
    
    // Flujo Alterno 1.2: Mensaje genérico por seguridad (evita enumeración de usuarios)
    if (!user) {
      return { message: 'Si el correo existe, recibirá instrucciones.' };
    }

    const recoveryCode = Math.floor(100000 + Math.random() * 900000).toString();
    user.recoveryCode = recoveryCode;
    await this.userRepository.save(user);

    // Envío del código con reintentos automáticos (misma política que CU-12 4.2)
    await this.mailRetryQueue.sendWithRetry({
      to: user.email,
      subject: 'Recuperación de Contraseña - ConstructING',
      text: `Su código temporal de recuperación es: ${recoveryCode}. Ingréselo en la aplicación junto con su nueva contraseña.`,
    });

    return { message: 'Si el correo existe, recibirá instrucciones.' };
  }

  /**
   * CU-03: Paso 2 - Validar código y almacenar nueva contraseña cifrada
   */
  async resetPassword(dto: { email: string; code: string; newPassword: string }) {
    const user = await this.userRepository.findOne({ where: { email: dto.email } });
    
    if (!user || user.recoveryCode !== dto.code) {
      throw new UnauthorizedException('Código inválido o expirado.');
    }

    // CU-11 + CU-03 Paso 2: la nueva contraseña cumple la política y se
    // almacena encriptada (bcrypt), nunca en texto plano.
    validatePasswordPolicy(dto.newPassword);
    user.passwordHash = await bcrypt.hash(dto.newPassword, SALT_ROUNDS);
    user.recoveryCode = null; // Invalida el código para re-utilizaciones
    
    await this.userRepository.save(user);
    return { message: 'Contraseña actualizada exitosamente. Ya puede iniciar sesión.' };
  }

  /**
   * CU-04: Cierre de Sesión (Destrucción de tokens en cliente)
   */
  async logout() {
    return { 
      message: 'Sesión finalizada exitosamente. El token debe ser destruido en el dispositivo cliente.' 
    };
  }
}