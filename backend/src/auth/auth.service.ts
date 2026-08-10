import { Injectable, UnauthorizedException, ConflictException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { MailerService } from '@nestjs-modules/mailer'; // <-- Nueva importación
import { UserEntity } from './user.entity';

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(UserEntity)
    private readonly userRepository: Repository<UserEntity>,
    private readonly jwtService: JwtService,
    private readonly mailerService: MailerService, // <-- Inyección de dependencias
  ) {}

  async register(dto: { email: string; password: string; role: string }) {
    const existingUser = await this.userRepository.findOne({ where: { email: dto.email } });
    if (existingUser) {
      throw new ConflictException('El correo ya se encuentra en uso.');
    }

    const saltRounds = 10;
    const hashedPassword = await bcrypt.hash(dto.password, saltRounds);

    const newUser = this.userRepository.create({
      email: dto.email,
      passwordHash: hashedPassword,
      role: dto.role,
    });

    await this.userRepository.save(newUser);

    // CU-12: Enviar correo de bienvenida automáticamente (Asíncrono)
    await this.mailerService.sendMail({
      to: newUser.email,
      subject: '¡Bienvenido a ConstructING!',
      text: `Hola. Tu cuenta con el rol de ${newUser.role} ha sido creada exitosamente. Ya puedes ingresar al sistema para registrar tus obras.`,
    });
    
    return { message: 'Usuario registrado exitosamente', userId: newUser.id };
  }

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

    return {
      access_token,
      role: user.role,
      message: 'Autenticación exitosa',
    };
  }

  // CU-03: Paso 1 - Enviar código de recuperación
  async forgotPassword(email: string) {
    const user = await this.userRepository.findOne({ where: { email } });
    
    // Flujo Alterno 1.2: Mensaje genérico por seguridad para evitar enumeración de usuarios
    if (!user) {
      return { message: 'Si el correo existe, recibirá instrucciones.' };
    }

    // Generar un código temporal de 6 dígitos
    const recoveryCode = Math.floor(100000 + Math.random() * 900000).toString();
    user.recoveryCode = recoveryCode;
    await this.userRepository.save(user);

    // Enviar el correo a través de Ethereal
    await this.mailerService.sendMail({
      to: user.email,
      subject: 'Recuperación de Contraseña - ConstructING',
      text: `Su código temporal de recuperación es: ${recoveryCode}. Ingréselo en la aplicación junto con su nueva contraseña para restablecer el acceso.`,
    });

    return { message: 'Si el correo existe, recibirá instrucciones.' };
  }

  // CU-03: Paso 2 - Validar código y guardar nueva contraseña
  async resetPassword(dto: { email: string; code: string; newPassword: string }) {
    const user = await this.userRepository.findOne({ where: { email: dto.email } });
    
    if (!user || user.recoveryCode !== dto.code) {
      throw new UnauthorizedException('Código inválido o expirado.');
    }

    // Encriptar la nueva contraseña cumpliendo con el CU-11
    const saltRounds = 10;
    user.passwordHash = await bcrypt.hash(dto.newPassword, saltRounds);
    
    // Invertir el código para que no pueda ser re-utilizado (Seguridad)
    user.recoveryCode = null; 
    
    await this.userRepository.save(user);
    return { message: 'Contraseña actualizada exitosamente. Ya puede iniciar sesión.' };
  }

  // CU-04: Cerrar Sesión
  async logout() {
    // En arquitecturas Stateless basadas en JWT, la revocación real ocurre en el cliente
    // destruyendo el token del Keystore/Keychain local. El backend confirma la invalidación.
    return { 
      message: 'Sesión finalizada exitosamente. El token debe ser destruido en el dispositivo cliente.' 
    };
  }
}