import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MailerModule } from '@nestjs-modules/mailer';
import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { UserEntity } from './user.entity';
import { MailRetryQueueService } from './mail-retry-queue.service';
import { WorkEntity } from '../works/entities/work.entity';
import { WorkInvitationEntity } from '../works/entities/work-invitation.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([UserEntity, WorkEntity, WorkInvitationEntity]),
    JwtModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => ({
        secret: configService.get<string>('JWT_SECRET', 'super-secret-key'),
        signOptions: { expiresIn: '24h' },
      }),
    }),
    // SMTP configurable por entorno (ver tabla en README). Por defecto apunta
    // a Ethereal (servicio de pruebas que captura los correos sin enviarlos
    // de verdad). Con credenciales inválidas el envío falla y la cola de
    // reintentos CU-12 4.2 lo encola; con credenciales reales despacha.
    MailerModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => ({
        transport: {
          host: configService.get<string>('MAIL_HOST', 'smtp.ethereal.email'),
          port: configService.get<number>('MAIL_PORT', 587),
          auth: {
            user: configService.get<string>('MAIL_USER', 'ethereal_user'),
            pass: configService.get<string>('MAIL_PASS', 'ethereal_pass'),
          },
        },
        defaults: {
          from: '"No Reply" <noreply@constructing.com>',
        },
      }),
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, MailRetryQueueService],
  // MailRetryQueueService se exporta para reutilizar los reintentos (CU-12
  // 4.2) en otros módulos, p. ej. las invitaciones de obra (CU-22).
  exports: [AuthService, MailRetryQueueService],
})
export class AuthModule {}