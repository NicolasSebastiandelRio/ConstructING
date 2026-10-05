import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AuditLogEntity } from './audit-log.entity';

export interface AuditLogInput {
  id: string;
  usuarioId: string;
  accion: string;
  detalle?: string | null;
  obraId?: string | null;
  coordenadas?: string | null;
}

/**
 * CU-60 (RF_08, RNF_S_03): Servicio de Audit Log (servidor central).
 *
 * Ensambla el registro consolidando la información del módulo de negocio
 * origen con el timestamp exacto (fecha y hora) emitido por el servidor e
 * inserta el registro inmutable en la tabla de auditoría: huella
 * permanente e imborrable de la operación. Solo INSERT/SELECT: no existen
 * operaciones de UPDATE ni DELETE sobre las filas (RNF_S_03).
 */
@Injectable()
export class AuditLogService {
  private readonly logger = new Logger(AuditLogService.name);

  constructor(
    @InjectRepository(AuditLogEntity)
    private readonly repository: Repository<AuditLogEntity>,
  ) {}

  /** CU-60 pasos 2-4: inserta el registro inmutable con timestamp del servidor. */
  async log(input: AuditLogInput): Promise<AuditLogEntity> {
    if (!input.usuarioId || !input.accion) {
      throw new BadRequestException(
        'El registro de auditoría requiere usuario y tipo de acción.',
      );
    }
    const fila = this.repository.create({
      id: input.id,
      usuarioId: input.usuarioId,
      accion: input.accion,
      detalle: input.detalle ?? null,
      obraId: input.obraId ?? null,
      coordenadas: input.coordenadas ?? null,
    });
    const guardada = await this.repository.save(fila);
    this.logger.log(
      `AUDIT (CU-60): ${input.usuarioId} · ${input.accion}` +
        (input.detalle ? ` · ${input.detalle}` : ''),
    );
    return guardada;
  }

  /** Consulta de la hoja forense (descendente; insumo del CU-63). */
  async findAll(): Promise<AuditLogEntity[]> {
    return this.repository.find({ order: { createdAt: 'DESC' } });
  }

  async findByObra(obraId: string): Promise<AuditLogEntity[]> {
    return this.repository.find({
      where: { obraId },
      order: { createdAt: 'DESC' },
    });
  }

  /** Registro único por id (verificación de sello). */
  async findOne(id: string): Promise<AuditLogEntity> {
    const fila = await this.repository.findOne({ where: { id } });
    if (!fila) {
      throw new NotFoundException(
        `El registro de auditoría ${id} no fue encontrado.`,
      );
    }
    return fila;
  }
}
