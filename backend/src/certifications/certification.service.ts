import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Repository } from 'typeorm';
import { CertificationEntity } from './certification.entity';

export interface CertificationSignInput {
  /** Identificador del acta (uuid asignado por el dispositivo, CU-56). */
  id: string;
  hitoId: string;
  obraId: string;
  firmante?: string | null;
  archivoNombre: string;
  /** PDF consolidado y finalizado, en memoria. */
  bytes: Buffer;
}

/**
 * CU-59 (RF_08, RNF_C_05): motor criptográfico de la tabla de
 * certificaciones.
 *
 * Sella el acta técnica consolidada: calcula el hash SHA-256 de la
 * totalidad del documento binario, lo almacena en la tabla de
 * certificaciones de la BD y persiste el archivo. El documento legal queda
 * sellado lógicamente contra modificaciones post-firma: el identificador
 * cambiaría radicalmente si se altera un solo byte del original.
 */
@Injectable()
export class CertificationService {
  private readonly logger = new Logger(CertificationService.name);

  constructor(
    @InjectRepository(CertificationEntity)
    private readonly repository: Repository<CertificationEntity>,
  ) {}

  private uploadDir(): string {
    return (
      process.env.CERTIFICATION_UPLOAD_DIR ||
      join(process.cwd(), 'uploads', 'certifications')
    );
  }

  /** CU-59 paso 2: hash SHA-256 de la totalidad del documento binario. */
  private sha256(buffer: Buffer): string {
    return createHash('sha256').update(buffer).digest('hex').toUpperCase();
  }

  /**
   * CU-59 paso 4: sella el acta. El sello es inalterable: un acta ya
   * firmada no se vuelve a modificar (mismo id con hash distinto se
   * rechaza; mismo id con mismo hash es idempotente).
   */
  async sign(input: CertificationSignInput): Promise<CertificationEntity> {
    if (!input.bytes || input.bytes.length === 0) {
      throw new BadRequestException('El acta PDF consolidada es obligatoria.');
    }
    const hashSha256 = this.sha256(input.bytes);
    const existente = await this.repository.findOne({ where: { id: input.id } });
    if (existente) {
      if (existente.hashSha256 !== hashSha256) {
        throw new BadRequestException(
          'El acta ya fue sellada con otro hash: el documento no puede modificarse post-firma (CU-59).',
        );
      }
      return existente;
    }
    const dir = this.uploadDir();
    await mkdir(dir, { recursive: true });
    await writeFile(join(dir, `${input.id}.pdf`), input.bytes);
    const fila = this.repository.create({
      id: input.id,
      hitoId: input.hitoId,
      obraId: input.obraId,
      hashSha256,
      archivoNombre: input.archivoNombre,
      firmante: input.firmante ?? null,
    });
    const guardada = await this.repository.save(fila);
    this.logger.log(`Acta ${input.id} sellada (CU-59): hash=${hashSha256}.`);
    return guardada;
  }

  /** CU-61 (futuro): fila de certificación del hito para verificar integridad. */
  async findByHito(hitoId: string): Promise<CertificationEntity> {
    const fila = await this.repository.findOne({ where: { hitoId } });
    if (!fila) {
      throw new NotFoundException(`El hito ${hitoId} no tiene acta sellada.`);
    }
    return fila;
  }

  /** Descarga del acta sellada (fallback remoto del CU-54, paso 2). */
  async loadFile(
    hitoId: string,
  ): Promise<{ buffer: Buffer; filename: string; contentType: string }> {
    const fila = await this.findByHito(hitoId);
    let buffer: Buffer;
    try {
      buffer = await readFile(join(this.uploadDir(), `${fila.id}.pdf`));
    } catch {
      throw new NotFoundException('El archivo del acta no está disponible.');
    }
    return { buffer, filename: fila.archivoNombre, contentType: 'application/pdf' };
  }
}
