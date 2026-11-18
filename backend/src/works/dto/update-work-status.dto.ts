import { IsEnum } from 'class-validator';
import { WorkStatus } from '../entities/work.entity';

/**
 * CU-20: cambio de fase global de la obra. Sólo admite valores del enum
 * WorkStatus; el archivado NO entra por este endpoint (pertenece a CU-21).
 */
export class UpdateWorkStatusDto {
  @IsEnum(WorkStatus, { message: 'Estado de obra inválido.' })
  estado!: WorkStatus;
}