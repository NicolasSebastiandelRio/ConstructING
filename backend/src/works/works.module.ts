import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { WorksService } from './works.service';
import { InvitationsService } from './invitations.service';
import { WorksController } from './works.controller';
import { WorkEntity } from './entities/work.entity';
import { WorkInvitationEntity } from './entities/work-invitation.entity';
import { UsersModule } from '../users/users.module'; // O AuthModule según corresponda
import { AuthModule } from '../auth/auth.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([WorkEntity, WorkInvitationEntity]),
    UsersModule, // Asegura la disponibilidad de los repositorios de usuarios
    AuthModule, // Reutiliza la cola de reintentos SMTP (CU-12 4.2) en CU-22
  ],
  controllers: [WorksController],
  providers: [WorksService, InvitationsService],
  exports: [WorksService, InvitationsService],
})
export class WorksModule {}