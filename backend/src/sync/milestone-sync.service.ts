import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { MilestoneSyncEntity } from './milestone-sync.entity';

export interface MilestoneSyncPayload {
  id: string;
  obraId: string;
  nombre: string;
  descripcion?: string | null;
  duracionDias: number;
  estado: string;
  esCritico?: boolean;
  /** ISO de la última modificación local (CU-47). */
  updatedAtLocal?: string | null;
}

export interface MilestoneSyncVerdict {
  synced: boolean;
  conflict: boolean;
  /** Versión final del registro (la vigente tras resolver el conflicto). */
  finalState: {
    id: string;
    nombre: string;
    duracionDias: number;
    estado: string;
    updatedAtLocal: string | null;
  };
}

/**
 * CU-44 (motor de sincronización, parte de hitos) + CU-47 (conflictos).
 *
 * Inserta el registro en la base maestra. Si ya existía y ambos lados
 * modificaron el registro, aplica la política de última modificación
 * comparando `updatedAtLocal` (paso 2), sobrescribe la versión obsoleta
 * (paso 4) y registra la acción en la traza de auditoría (CU-60 transitoria
 * hasta el módulo de Audit Log de PT-07).
 */
@Injectable()
export class MilestoneSyncService {
  private readonly logger = new Logger(MilestoneSyncService.name);

  constructor(
    @InjectRepository(MilestoneSyncEntity)
    private readonly repository: Repository<MilestoneSyncEntity>,
  ) {}

  async upsert(payload: MilestoneSyncPayload): Promise<MilestoneSyncVerdict> {
    const incomingDate = payload.updatedAtLocal
      ? new Date(payload.updatedAtLocal)
      : new Date(0);

    const existing = await this.repository.findOne({ where: { id: payload.id } });

    if (!existing) {
      const created = this.repository.create({
        id: payload.id,
        obraId: payload.obraId,
        nombre: payload.nombre,
        descripcion: payload.descripcion ?? null,
        duracionDias: payload.duracionDias,
        estado: payload.estado,
        esCritico: payload.esCritico ?? false,
        updatedAtLocal: incomingDate,
      });
      const saved = await this.repository.save(created);
      this.logger.log(
        `CU-44: hito ${payload.id} insertado en la base maestra (obra ${payload.obraId}).`,
      );
      return this.verdict(saved, false);
    }

    // CU-47 paso 2: colisión de versiones → última modificación gana.
    const incomingWins = incomingDate >= (existing.updatedAtLocal ?? new Date(0));
    if (incomingWins) {
      existing.nombre = payload.nombre;
      existing.descripcion = payload.descripcion ?? existing.descripcion;
      existing.duracionDias = payload.duracionDias;
      existing.estado = payload.estado;
      existing.esCritico = payload.esCritico ?? existing.esCritico;
      existing.updatedAtLocal = incomingDate;
    }
    const saved = await this.repository.save(existing);

    this.logger.log(
      `CU-47: conflicto resuelto para hito ${payload.id}: ` +
        `versión ${incomingWins ? 'local (incoming)' : 'remota (existente)'} prevalece ` +
        '(última modificación). Acción registrada en Audit Log (CU-60 transitorio).',
    );

    return this.verdict(saved, true);
  }

  private verdict(
    entity: MilestoneSyncEntity,
    conflict: boolean,
  ): MilestoneSyncVerdict {
    return {
      synced: true,
      conflict,
      finalState: {
        id: entity.id,
        nombre: entity.nombre,
        duracionDias: entity.duracionDias,
        estado: entity.estado,
        updatedAtLocal: entity.updatedAtLocal
          ? entity.updatedAtLocal.toISOString()
          : null,
      },
    };
  }
}
