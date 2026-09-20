import { Injectable, Logger } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { mkdir, readFile, rm, stat, appendFile } from 'node:fs/promises';
import { join } from 'node:path';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { EvidenceSyncEntity } from './evidence-sync.entity';

export interface EvidenceSyncMetadata {
  id: string;
  hitoId: string;
  obraId: string;
  tipo: string;
  nota?: string | null;
  latitud: number;
  longitud: number;
  precisionM: number;
  fechaCaptura: string;
  duracionSeg?: number | null;
  tamanoBytes: number;
  checksum: string;
  marcaTexto: string;
}

export type EvidenceUploadOutcome =
  | { result: 'synced' }
  /** CU-45 Alt. 2.1/2.2: el checksum recibido no coincide → retransmitir. */
  | { result: 'corrupted' };

/**
 * CU-44 (subida de evidencias) + CU-45 (integridad) + CU-46 (carga
 * reanudable).
 *
 * Los binarios se almacenan en el directorio `UPLOAD_DIR` con el nombre
 * `<id><ext>`; los metadatos van a la base maestra. Toda subida se valida
 * comparando el SHA-256 calculado sobre el archivo recibido contra el
 * checksum original declarado por el dispositivo.
 */
@Injectable()
export class EvidenceSyncService {
  private readonly logger = new Logger(EvidenceSyncService.name);

  constructor(
    @InjectRepository(EvidenceSyncEntity)
    private readonly repository: Repository<EvidenceSyncEntity>,
  ) {}

  private uploadDir(): string {
    return process.env.UPLOAD_DIR || join(process.cwd(), 'uploads', 'evidences');
  }

  private async ensureDir(): Promise<string> {
    const dir = this.uploadDir();
    await mkdir(dir, { recursive: true });
    return dir;
  }

  private pathOf(id: string, ext = '.bin'): string {
    return join(this.uploadDir(), `${id}${ext}`);
  }

  /** CU-45 paso 2: calcula el checksum del archivo recién recibido. */
  private sha256(buffer: Buffer): string {
    return createHash('sha256').update(buffer).digest('hex').toUpperCase();
  }

  /**
   * CU-44 paso 2 + CU-45: subida completa (fotos y videos chicos).
   * Si el checksum no coincide, descarta el archivo corrupto (Alt. 2.2) y
   * ordena la retransmisión.
   */
  async uploadComplete(
    payload: EvidenceSyncMetadata,
    bytes: Buffer,
  ): Promise<EvidenceUploadOutcome> {
    const receivedChecksum = this.sha256(bytes);
    if (receivedChecksum !== payload.checksum.toUpperCase()) {
      this.logger.warn(
        `CU-45 Alt.: checksum divergente para evidencia ${payload.id} ` +
          `(esperado ${payload.checksum}, recibido ${receivedChecksum}). ` +
          'Archivo corrupto descartado; se ordena retransmisión.',
      );
      await rm(this.assemblyPathOf(payload.id), { force: true });
      return { result: 'corrupted' };
    }

    // CU-45 paso 4: ensamblado íntegro → se archiva con extensión final.
    const dir = await this.ensureDir();
    const assembly = this.assemblyPathOf(payload.id);
    const { writeFile, rename } = await import('node:fs/promises');
    await writeFile(assembly, bytes);
    const archivoNombre = `${payload.id}.${payload.tipo === 'Video' ? 'mp4' : 'jpg'}`;
    await rename(assembly, join(dir, archivoNombre));

    await this.persist(payload, archivoNombre);
    this.logger.log(
      `CU-45: integridad validada bit a bit para evidencia ${payload.id} ` +
        `(${bytes.length} bytes, SHA-256 OK). Persistida en la nube.`,
    );
    return { result: 'synced' };
  }

  /** Archivo de ensamblado en curso (CU-46: bloques parciales). */
  private assemblyPathOf(id: string): string {
    return join(this.uploadDir(), `${id}.bin`);
  }

  /** CU-46 paso 2: tamaño exacto en bytes ya recibido del archivo. */
  async receivedBytes(id: string): Promise<number> {
    try {
      const info = await stat(this.assemblyPathOf(id));
      return info.size;
    } catch {
      return 0;
    }
  }

  /**
   * CU-46 pasos 3-4: transmite únicamente el bloque restante; al completar
   * el total, ensambla y ejecuta el CU-45 para validarlo.
   */
  async uploadChunk(
    id: string,
    offset: number,
    bytes: Buffer,
    meta: EvidenceSyncMetadata,
  ): Promise<EvidenceUploadOutcome> {
    const dir = await this.ensureDir();
    const path = this.assemblyPathOf(id);
    const currentSize = await this.receivedBytes(id);
    if (offset !== currentSize) {
      this.logger.warn(
        `CU-46: offset inconsistente para evidencia ${id} ` +
          `(solicitado ${offset}, en disco ${currentSize}).`,
      );
      return { result: 'corrupted' };
    }
    await appendFile(path, bytes);

    const total = meta.tamanoBytes;
    const finalSize = await stat(path).then((s) => s.size);
    if (finalSize < total) {
      return { result: 'synced' }; // parcial: aún no se valida
    }

    // Fragmento final: ensamblado completo → validación CU-45.
    const full = await readFile(path);
    if (full.length !== total) {
      await rm(path, { force: true });
      return { result: 'corrupted' };
    }
    if (this.sha256(full) !== meta.checksum.toUpperCase()) {
      await rm(path, { force: true });
      this.logger.warn(
        `CU-45 Alt.: checksum divergente tras reanudar ${id}; fragmentos descartados.`,
      );
      return { result: 'corrupted' };
    }

    // CU-46 paso 4: ensamblado íntegro → se archiva con extensión final.
    const archivoNombre = `${id}.${meta.tipo === 'Video' ? 'mp4' : 'jpg'}`;
    const { rename } = await import('node:fs/promises');
    await rename(path, join(dir, archivoNombre));
    await this.persist(meta, archivoNombre);
    this.logger.log(
      `CU-46/CU-45: carga reanudable completada y validada para evidencia ${id}.`,
    );
    return { result: 'synced' };
  }

  private async persist(
    meta: EvidenceSyncMetadata,
    archivoNombre: string,
  ): Promise<void> {
    const existing = await this.repository.findOne({ where: { id: meta.id } });
    const entity = this.repository.create({
      id: meta.id,
      hitoId: meta.hitoId,
      obraId: meta.obraId,
      tipo: meta.tipo,
      nota: meta.nota ?? null,
      latitud: meta.latitud,
      longitud: meta.longitud,
      precisionM: meta.precisionM,
      fechaCaptura: new Date(meta.fechaCaptura),
      duracionSeg: meta.duracionSeg ?? null,
      tamanoBytes: meta.tamanoBytes,
      checksum: meta.checksum,
      marcaTexto: meta.marcaTexto,
      archivoNombre,
    });
    if (existing) {
      entity.createdAt = existing.createdAt;
    }
    await this.repository.save(entity);
  }
}
