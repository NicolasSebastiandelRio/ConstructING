import { Controller, Post, Body, HttpCode, HttpStatus } from '@nestjs/common';
import { AuthService } from './auth.service';

@Controller('auth') // Define el prefijo base: /auth
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  /**
   * Endpoint de Registro (CU-06 y CU-10, con reclamo de invitación CU-22)
   * Ruta final: POST /auth/register
   */
  @Post('register')
  async register(
    @Body() dto: { email: string; password: string; role: string; invitationCode?: string },
  ) {
    return this.authService.register(dto);
  }

  /**
   * Endpoint de Inicio de Sesión (CU-01 y CU-05)
   * Ruta final: POST /auth/login
   */
  @Post('login')
  @HttpCode(HttpStatus.OK) // Retorna 200 OK en lugar de 201 Created por defecto
  async login(
    @Body() dto: { email: string; password: string },
  ) {
    return this.authService.login(dto);
  }

  /**
   * Endpoint: Solicitar Código de Recuperación (CU-03)
   */
  @Post('forgot-password')
  @HttpCode(HttpStatus.OK)
  async forgotPassword(@Body() dto: { email: string }) {
    return this.authService.forgotPassword(dto.email);
  }

  /**
   * Endpoint: Restablecer Contraseña (CU-03)
   */
  @Post('reset-password')
  @HttpCode(HttpStatus.OK)
  async resetPassword(
    @Body() dto: { email: string; code: string; newPassword: string },
  ) {
    return this.authService.resetPassword(dto);
  }

  /**
   * Endpoint de Cierre de Sesión (CU-04)
   */
  @Post('logout')
  @HttpCode(HttpStatus.OK)
  async logout() {
    return this.authService.logout();
  }
}