import { Test } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { MilestoneSyncService, MilestoneSyncPayload } from './milestone-sync.service';
import { MilestoneSyncEntity } from './milestone-sync.entity';

const repositoryMockFactory = () => ({
  findOne: jest.fn(),
  create: jest.fn((dto) => dto),
  save: jest.fn(async (entity) => ({
    ...entity,
    updatedAtLocal: entity.updatedAtLocal ?? null,
  })),
});

describe('MilestoneSyncService - CU-47 (Resolver Conflictos Temporales)', () => {
  let service: MilestoneSyncService;
  let repository: any;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        MilestoneSyncService,
        { provide: getRepositoryToken(MilestoneSyncEntity), useFactory: repositoryMockFactory },
      ],
    }).compile();
    service = module.get(MilestoneSyncService);
    repository = module.get(getRepositoryToken(MilestoneSyncEntity));
  });

  const basePayload = (): MilestoneSyncPayload => ({
    id: '11111111-1111-1111-1111-111111111111',
    obraId: 'w1',
    nombre: 'Cimientos',
    duracionDias: 10,
    estado: 'Pendiente',
    esCritico: false,
    updatedAtLocal: '2026-09-19T10:00:00Z',
  });

  it('CU-44 paso 2: inserta el registro nuevo en la base maestra', async () => {
    repository.findOne.mockResolvedValue(null);
    const verdict = await service.upsert(basePayload());
    expect(verdict.synced).toBe(true);
    expect(verdict.conflict).toBe(false);
    expect(repository.save).toHaveBeenCalled();
  });

  it('CU-47 paso 4: la última modificación sobrescribe la versión obsoleta', async () => {
    repository.findOne.mockResolvedValue({
      id: basePayload().id,
      obraId: 'w1',
      nombre: 'Cimientos (viejo)',
      descripcion: null,
      duracionDias: 10,
      estado: 'Pendiente',
      esCritico: false,
      updatedAtLocal: new Date('2026-09-19T08:00:00Z'),
    });
    const payload = { ...basePayload(), estado: 'En Ejecución' };
    const verdict = await service.upsert(payload);

    expect(verdict.conflict).toBe(true);
    expect(verdict.finalState.estado).toBe('En Ejecución');
  });

  it('CU-47 paso 2: la versión local obsoleta NO sobrescribe la remota', async () => {
    repository.findOne.mockResolvedValue({
      id: basePayload().id,
      obraId: 'w1',
      nombre: 'Cimientos (remoto vigente)',
      descripcion: null,
      duracionDias: 10,
      estado: 'Certificado',
      esCritico: false,
      updatedAtLocal: new Date('2026-09-19T12:00:00Z'),
    });
    const verdict = await service.upsert(basePayload());

    expect(verdict.conflict).toBe(true);
    // La versión remota más reciente prevalece (política de última modificación).
    expect(verdict.finalState.estado).toBe('Certificado');
    expect(verdict.finalState.nombre).toBe('Cimientos (remoto vigente)');
  });
});
