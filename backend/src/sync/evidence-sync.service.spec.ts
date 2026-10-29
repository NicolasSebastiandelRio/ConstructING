import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { EvidenceSyncService } from './evidence-sync.service';
import { EvidenceSyncEntity } from './evidence-sync.entity';
import { EvidenceSyncMetadata } from './evidence-sync.service';
import { createHash } from 'node:crypto';

const repositoryMockFactory = () => ({
  findOne: jest.fn().mockResolvedValue(null),
  create: jest.fn((dto) => dto),
  save: jest.fn(async (entity) => entity),
});

const sha256 = (buffer: Buffer) =>
  createHash('sha256').update(buffer).digest('hex').toUpperCase();

const baseMeta = (checksum: string): EvidenceSyncMetadata => ({
  id: '22222222-2222-2222-2222-222222222222',
  hitoId: 'h1',
  obraId: 'w1',
  tipo: 'Foto',
  nota: 'Fisura menor',
  latitud: -34.6037,
  longitud: -58.3816,
  precisionM: 5,
  fechaCaptura: '2026-09-19T10:00:00Z',
  duracionSeg: null,
  tamanoBytes: 3,
  checksum,
  marcaTexto: 'ConstructING',
});

describe('EvidenceSyncService - CU-44/CU-45/CU-46', () => {
  let service: EvidenceSyncService;
  let repository: any;

  beforeEach(async () => {
    process.env.UPLOAD_DIR = `${process.cwd()}/tmp-test-uploads`;
    const module = await Test.createTestingModule({
      providers: [
        EvidenceSyncService,
        { provide: getRepositoryToken(EvidenceSyncEntity), useFactory: repositoryMockFactory },
      ],
    }).compile();
    service = module.get(EvidenceSyncService);
    repository = module.get(getRepositoryToken(EvidenceSyncEntity));
  });

  it('CU-44 paso 2 + CU-45 paso 4: subida íntegra retorna synced', async () => {
    const bytes = Buffer.from([1, 2, 3]);
    const outcome = await service.uploadComplete(baseMeta(sha256(bytes)), bytes);
    expect(outcome).toEqual({ result: 'synced' });
    expect(repository.save).toHaveBeenCalled();
  });

  it('CU-45 Alt. 2.1/2.2: checksum divergente descarta el archivo y ordena retransmisión', async () => {
    const bytes = Buffer.from([9, 9, 9]);
    const outcome = await service.uploadComplete(baseMeta(sha256(Buffer.from([1, 1, 1]))), bytes);
    expect(outcome).toEqual({ result: 'corrupted' });
    expect(repository.save).not.toHaveBeenCalled();
  });

  it('CU-46: consulta offset, transmite el bloque restante y valida al completar', async () => {
    const bytes = Buffer.from([1, 2, 3, 4, 5, 6]);
    const meta = { ...baseMeta(sha256(bytes)), tamanoBytes: 6 };

    // Paso 2: sin bloques previos el offset es 0.
    expect(await service.receivedBytes(meta.id)).toBe(0);

    // Paso 3: primer bloque parcial (3 bytes de 6).
    const partial = await service.uploadChunk(meta.id, 0, bytes.subarray(0, 3), meta);
    expect(partial).toEqual({ result: 'synced' });
    expect(await service.receivedBytes(meta.id)).toBe(3);

    // Fragmento final: ensambla + ejecuta CU-45 + archiva.
    const final = await service.uploadChunk(meta.id, 3, bytes.subarray(3), meta);
    expect(final).toEqual({ result: 'synced' });
    expect(repository.save).toHaveBeenCalled();
    // El ensamblado se archiva: ya no queda bloque pendiente.
    expect(await service.receivedBytes(meta.id)).toBe(0);
  });

  it('CU-46 Alt.: offset inconsistente rechaza el bloque', async () => {
    const bytes = Buffer.from([1, 2, 3]);
    const meta = { ...baseMeta(sha256(bytes)) };
    const outcome = await service.uploadChunk(meta.id, 99, bytes, meta);
    expect(outcome).toEqual({ result: 'corrupted' });
  });
});
