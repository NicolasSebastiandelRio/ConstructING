import { Injectable, UnauthorizedException, ConflictException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { UserEntity } from './user.entity';

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(UserEntity)
    private readonly userRepository: Repository<UserEntity>,
    private readonly jwtService: JwtService,
  ) {}

  /**
   * CU-06 y CU-11: Registro y Encriptación de Credenciales
   */
  async register(dto: { email: string; password: string; role: string }) {
    // CU-10: Validar unicidad en la base de datos real
    const existingUser = await this.userRepository.findOne({ where: { email: dto.email } });
    if (existingUser) {
      throw new ConflictException('El correo ya se encuentra en uso.');
    }

    // CU-11: Encriptar la contraseña con bcrypt
    const saltRounds = 10;
    const hashedPassword = await bcrypt.hash(dto.password, saltRounds);

    // Creamos la instancia de la entidad (Patrón Data Mapper)
    const newUser = this.userRepository.create({
      email: dto.email,
      passwordHash: hashedPassword,
      role: dto.role,
    });

    // Persistimos en PostgreSQL (Supabase)
    await this.userRepository.save(newUser);
    
    return { message: 'Usuario registrado exitosamente', userId: newUser.id };
  }

  /**
   * CU-01 y CU-02: Inicio de Sesión y Validación de Credenciales
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

    // CU-05: Generación de token JWT para sesión persistente
    const payload = { sub: user.id, email: user.email, role: user.role };
    const access_token = this.jwtService.sign(payload);

    return {
      access_token,
      role: user.role,
      message: 'Autenticación exitosa',
    };
  }
}