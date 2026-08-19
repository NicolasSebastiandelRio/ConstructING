import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { WorksService } from './works.service';
import { WorksController } from './works.controller';
import { WorkEntity } from './entities/work.entity';
import { UsersModule } from '../users/users.module'; // O AuthModule según corresponda

@Module({
  imports: [
    TypeOrmModule.forFeature([WorkEntity]),
    UsersModule, // Asegura la disponibilidad de los repositorios de usuarios
  ],
  controllers: [WorksController],
  providers: [WorksService],
  exports: [WorksService],
})
export class WorksModule {}