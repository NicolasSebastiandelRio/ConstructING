import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuditLogEntity } from './audit-log.entity';
import { AuditLogService } from './audit-log.service';
import { AuditLogController } from './audit-log.controller';

/**
 * Módulo de Audit Log (CU-60, PT-07): huella permanente e imborrable de
 * las transacciones críticas (RF_08, RNF_S_03).
 */
@Module({
  imports: [TypeOrmModule.forFeature([AuditLogEntity])],
  controllers: [AuditLogController],
  providers: [AuditLogService],
})
export class AuditLogsModule {}
