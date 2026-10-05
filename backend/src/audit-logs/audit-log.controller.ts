import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
} from '@nestjs/common';
import { AuditLogEntity } from './audit-log.entity';
import { AuditLogInput, AuditLogService } from './audit-log.service';

/**
 * Endpoints del Servicio de Audit Log (CU-60, RF_08/RNF_S_03).
 *
 * Solo POST (inserción inmutable) y GET (consulta): no existen endpoints
 * de UPDATE ni DELETE sobre la tabla de auditoría (RNF_S_03).
 */
@Controller()
export class AuditLogController {
  constructor(private readonly auditLogService: AuditLogService) {}

  /** CU-60: registra una transacción crítica (timestamp del servidor). */
  @Post('audit-logs')
  log(@Body() input: AuditLogInput): Promise<AuditLogEntity> {
    for (const key of ['id', 'usuarioId', 'accion']) {
      if (!input?.[key as keyof AuditLogInput]) {
        throw new BadRequestException(
          `Falta el campo obligatorio: ${key}.`,
        );
      }
    }
    return this.auditLogService.log(input);
  }

  /** Hoja forense completa (CU-63, futuro). */
  @Get('audit-logs')
  findAll(): Promise<AuditLogEntity[]> {
    return this.auditLogService.findAll();
  }

  /** Historial de una obra (CU-63, futuro). */
  @Get('audit-logs/obra/:obraId')
  findByObra(@Param('obraId') obraId: string): Promise<AuditLogEntity[]> {
    return this.auditLogService.findByObra(obraId);
  }

  @Get('audit-logs/:id')
  findOne(@Param('id') id: string): Promise<AuditLogEntity> {
    return this.auditLogService.findOne(id);
  }
}
