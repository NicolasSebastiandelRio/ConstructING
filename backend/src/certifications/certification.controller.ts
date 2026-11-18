import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Param,
  Post,
  Res,
  StreamableFile,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import type { Response } from 'express';
import { FileInterceptor } from '@nestjs/platform-express';
import { CertificationEntity } from './certification.entity';
import { CertificationService, CertificationSignInput } from './certification.service';

type UploadedFileLike = { buffer: Buffer; size: number; originalname: string };

/**
 * Endpoints de la tabla de certificaciones (CU-59, PT-07).
 *
 * El dispositivo (Módulo de Certificación) envía el acta PDF consolidada
 * y el servidor la sella criptográficamente (SHA-256 inmutable).
 */
@Controller()
export class CertificationController {
  constructor(private readonly certificationService: CertificationService) {}

  /** CU-59: sella el acta consolidada (multipart: file + metadatos). */
  @Post('certifications')
  @UseInterceptors(FileInterceptor('file'))
  async sign(
    @UploadedFile() file: UploadedFileLike | undefined,
    @Body() body: Record<string, string>,
  ): Promise<CertificationEntity> {
    if (!file || !file.buffer || file.buffer.length === 0) {
      throw new BadRequestException('El acta PDF consolidada es obligatoria.');
    }
    for (const key of ['id', 'hitoId', 'obraId']) {
      if (!body[key]) {
        throw new BadRequestException(
          `Falta el metadato obligatorio: ${key}.`,
        );
      }
    }
    const input: CertificationSignInput = {
      id: body.id,
      hitoId: body.hitoId,
      obraId: body.obraId,
      firmante: body.firmante ?? null,
      archivoNombre:
        body.archivoNombre ?? `acta_${body.hitoId}.pdf`,
      bytes: file.buffer,
    };
    return this.certificationService.sign(input);
  }

  /** CU-59 paso 4 (consulta): la certificación sellada del hito. */
  @Get('certifications/hito/:hitoId')
  findByHito(@Param('hitoId') hitoId: string): Promise<CertificationEntity> {
    return this.certificationService.findByHito(hitoId);
  }

  /** Descarga del acta sellada (fallback remoto del CU-54). */
  @Get('certifications/hito/:hitoId/acta')
  async downloadActa(
    @Param('hitoId') hitoId: string,
    @Res({ passthrough: true }) res: Response,
  ): Promise<StreamableFile> {
    const file = await this.certificationService.loadFile(hitoId);
    res.set({
      'Content-Type': file.contentType,
      'Content-Disposition': `inline; filename="${file.filename}"`,
    });
    return new StreamableFile(file.buffer);
  }
}
