import { Injectable, UnauthorizedException, ConflictException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';

// Interfaz estricta para tipar los usuarios en memoria (previene el error 'never')
interface User {
  id: string;
  email: string;
  password: string;
  role: string;
}

@Injectable()
export class AuthService {
  constructor(private readonly jwtService: JwtService) {}

  // Tipamos explícitamente el arreglo como User[]
  private readonly users: User[] = [];

  /**
   * CU-06 y CU-11: Registro y Encriptación de Credenciales
   */
  async register(dto: { email: string; password: string; role: string }) {
    // CU-10: Validar unicidad de identidad
    const existingUser = this.users.find((u) => u.email === dto.email);
    if (existingUser) {
      throw new ConflictException('El correo ya se encuentra en uso.');
    }

    // CU-11: Encriptar la contraseña con bcrypt
    const saltRounds = 10;
    const hashedPassword = await bcrypt.hash(dto.password, saltRounds);

    const newUser: User = {
      id: Date.now().toString(),
      email: dto.email,
      password: hashedPassword,
      role: dto.role,
    };

    this.users.push(newUser);
    return { message: 'Usuario registrado exitosamente', userId: newUser.id };
  }

  /**
   * CU-01 y CU-02: Inicio de Sesión y Validación de Credenciales
   */
  async login(dto: { email: string; password: string }) {
    const user = this.users.find((u) => u.email === dto.email);
    if (!user) {
      throw new UnauthorizedException('Credenciales inválidas.');
    }

    const isPasswordValid = await bcrypt.compare(dto.password, user.password);
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