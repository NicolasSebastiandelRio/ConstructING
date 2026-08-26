import { Injectable, UnauthorizedException, ConflictException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { MailerService } from '@nestjs-modules/mailer';
import { UserEntity } from './user.entity';

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(UserEntity)
    private readonly userRepository: Repository<UserEntity>,
    private readonly jwtService: JwtService,
    private readonly mailerService: MailerService,
  ) {}

  /**
   * CU-06: Registro de nuevo usuario (Propietario o Profesional)
   */
  async register(dto: { email: string; password: string; role?: string; rol?: string; nombre?: string; matricula?: string }) {
    const userRole = dto.role || dto.rol || 'Propietario';
    const existingUser = await this.userRepository.findOne({ where: { email: dto.email } });
    
    if (existingUser) {
      throw new ConflictException('El correo ya se encuentra en uso.');
    }

    // CU-11: Encriptar credenciales de acceso con bcrypt
    const saltRounds = 10;
    const hashedPassword = await bcrypt.hash(dto.password, saltRounds);

    const newUser = this.userRepository.create({
      email: dto.email,
      passwordHash: hashedPassword,
      role: userRole,
    });

    await this.userRepository.save(newUser);

    // CU-12: Enviar correo de bienvenida automáticamente (Protegido con try/catch para entorno local)
    try {
      await this.mailerService.sendMail({
        to: newUser.email,
        subject: '¡Bienvenido a ConstructING!',
        text: `Hola. Tu cuenta con el rol de ${newUser.role} ha sido creada exitosamente. Ya puedes ingresar al sistema.`,
      });
    } catch (mailError) {
      console.warn('Advertencia: No se pudo despachar el correo SMTP (servidor no configurado).', mailError);
    }
    
    // Retornamos el objeto con el contrato exacto que UserModel.fromJson espera en el cliente
    return {
      id: newUser.id,
      nombre: dto.nombre || 'Usuario ConstructING',
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
        nombre: 'Usuario ConstructING',
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

    try {
      await this.mailerService.sendMail({
        to: user.email,
        subject: 'Recuperación de Contraseña - ConstructING',
        text: `Su código temporal de recuperación es: ${recoveryCode}. Ingréselo en la aplicación junto con su nueva contraseña.`,
      });
    } catch (mailError) {
      console.warn('Advertencia: No se pudo enviar el correo de recuperación.', mailError);
    }

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

    const saltRounds = 10;
    user.passwordHash = await bcrypt.hash(dto.newPassword, saltRounds);
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