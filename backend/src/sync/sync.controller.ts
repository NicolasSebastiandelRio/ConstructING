import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  UseInterceptors,
  UploadedFile,
  HttpCode,
  BadRequestException,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { MilestoneSyncService, MilestoneSyncPayload } from './milestone-sync.service';
import {
  EvidenceSyncService,
  EvidenceSyncMetadata,
  EvidenceUploadOutcome,
} from './evidence-sync.service';

type UploadedFileLike = { buffer: Buffer; size: number; originalname: string };

/**
 * Endpoints del motor de sincronización offline-first (CU-44..CU-47).
 *
 * El dispositivo (actor del CU-44) vuelca sus registros pendientes por
 * HTTPS; el servidor responde con HTTP 200 por paquete confirmado.
 */
@Controller()
export class SyncController {
  constructor(
    private readonly milestoneSync: MilestoneSyncService,
    private readonly evidenceSync: EvidenceSyncService,
  ) {}

  /** CU-44: volcado de un hito pendiente; CU-47 aplicado en caso de colisión. */
  @Post('sync/milestones')
  @HttpCode(200)
  syncMilestone(@Body() payload: MilestoneSyncPayload) {
    return this.milestoneSync.upsert(payload);
  }

  /** CU-44 paso 2 + CU-45: subida completa de una evidencia (multipart). */
  @Post('evidences')
  @UseInterceptors(FileInterceptor('file'))
  async uploadEvidence(
    @UploadedFile() file: UploadedFileLike | undefined,
    @Body() body: Record<string, string>,
  ): Promise<EvidenceUploadOutcome> {
    if (!file || !file.buffer || file.buffer.length === 0) {
      throw new BadRequestException('El archivo de evidencia es obligatorio.');
    }
    const meta = this.parseMeta(body);
    if (meta.tamanoBytes !== file.buffer.length) {
      throw new BadRequestException(
        'El tamaño del archivo recibido no coincide con el declarado.',
      );
    }
    return this.evidenceSync.uploadComplete(meta, file.buffer);
  }

  /** CU-46 paso 2: consulta el punto exacto de interrupción (bytes). */
  @Get('evidences/:id/offset')
  offset(@Param('id') id: string) {
    return this.evidenceSync.receivedBytes(id).then((bytes) => ({ id, bytes }));
  }

  /** CU-46 pasos 3-4: transmite únicamente el bloque restante (base64). */
  @Patch('evidences/:id/chunk')
  @HttpCode(200)
  async uploadChunk(
    @Param('id') id: string,
    @Body()
    body: {
      offset: number;
      bytesB64: string;
      meta: EvidenceSyncMetadata;
    },
  ): Promise<EvidenceUploadOutcome> {
    if (!body || typeof body.bytesB64 !== 'string' || body.bytesB64.length === 0) {
      throw new BadRequestException('El bloque de datos es obligatorio.');
    }
    const bytes = Buffer.from(body.bytesB64, 'base64');
    return this.evidenceSync.uploadChunk(id, Number(body.offset) || 0, bytes, body.meta);
  }

  private parseMeta(body: Record<string, string>): EvidenceSyncMetadata {
    const required = ['id', 'hitoId', 'obraId', 'tipo', 'latitud', 'longitud', 'checksum', 'marcaTexto'];
    for (const key of required) {
      if (!body[key]) {
        throw new BadRequestException(`Falta el metadato obligatorio: ${key}.`);
      }
    }
    return {
      id: body.id,
      hitoId: body.hitoId,
      obraId: body.obraId,
      tipo: body.tipo,
      nota: body.nota ?? null,
      latitud: Number(body.latitud),
      longitud: Number(body.longitud),
      precisionM: Number(body.precisionM ?? 0),
      fechaCaptura: body.fechaCaptura ?? new Date().toISOString(),
      duracionSeg: body.duracionSeg != null ? Number(body.duracionSeg) : null,
      tamanoBytes: Number(body.tamanoBytes ?? 0),
      checksum: String(body.checksum).toUpperCase(),
      marcaTexto: body.marcaTexto ?? '',
    };
  }
}
