// Forzamos el modo test ANTES del bootstrap para usar better-sqlite3 en memoria.
process.env.NODE_ENV = 'test';

import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { createHash } from 'node:crypto';
import { AppModule } from '../src/app.module';

const PDF_BYTES = Buffer.from('%PDF-1.4\n1 0 obj\n<< >>\nendobj\n%%EOF\n', 'utf8');

function sha256(buffer: Buffer): string {
  return createHash('sha256').update(buffer).digest('hex').toUpperCase();
}

describe('CU-59 Generar Hash de Acta PDF (E2E, PT-07)', () => {
  let app: INestApplication;
  const actaId = '11111111-1111-4111-8111-111111111111';
  const hitoId = '22222222-2222-4222-8222-222222222222';
  const obraId = '33333333-3333-4333-8333-333333333333';

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    await app.init();
  }, 30000);

  afterAll(async () => {
    if (app) {
      await app.close();
    }
  });

  it('sella el acta consolidada: 201 + hash SHA-256 de 64 hex', async () => {
    const response = await request(app.getHttpServer())
      .post('/certifications')
      .field('id', actaId)
      .field('hitoId', hitoId)
      .field('obraId', obraId)
      .field('firmante', 'Profesional')
      .attach('file', PDF_BYTES, 'acta_test.pdf');

    expect(response.status).toBe(201);
    expect(response.body.id).toBe(actaId);
    expect(response.body.hitoId).toBe(hitoId);
    expect(response.body.hashSha256).toBe(sha256(PDF_BYTES));
    expect(response.body.hashSha256).toMatch(/^[0-9A-F]{64}$/);
  });

  it('sellado inalterable: re-sellar el mismo id con otro contenido falla 400', async () => {
    const response = await request(app.getHttpServer())
      .post('/certifications')
      .field('id', actaId)
      .field('hitoId', hitoId)
      .field('obraId', obraId)
      .attach('file', Buffer.from('%PDF-1.5\nOTRO DOCUMENTO\n%%EOF\n'), 'otro.pdf');

    expect(response.status).toBe(400);
    expect(response.body.message).toContain('no puede modificarse post-firma');
  });

  it('idempotencia: re-sellar el mismo id con el mismo hash devuelve la fila', async () => {
    const response = await request(app.getHttpServer())
      .post('/certifications')
      .field('id', actaId)
      .field('hitoId', hitoId)
      .field('obraId', obraId)
      .attach('file', PDF_BYTES, 'acta_test.pdf');

    expect(response.status).toBe(201);
    expect(response.body.hashSha256).toBe(sha256(PDF_BYTES));
  });

  it('falta el acta → 400', async () => {
    const response = await request(app.getHttpServer())
      .post('/certifications')
      .field('id', '44444444-4444-4444-8444-444444444444')
      .field('hitoId', hitoId)
      .field('obraId', obraId);

    expect(response.status).toBe(400);
  });

  it('falta un metadato obligatorio (hitoId) → 400', async () => {
    const response = await request(app.getHttpServer())
      .post('/certifications')
      .field('id', '44444444-4444-4444-8444-444444444444')
      .attach('file', PDF_BYTES, 'acta_test.pdf');

    expect(response.status).toBe(400);
  });

  it('consulta: la certificación sellada del hito (CU-59 paso 4)', async () => {
    const response = await request(app.getHttpServer()).get(
      `/certifications/hito/${hitoId}`,
    );

    expect(response.status).toBe(200);
    expect(response.body.hashSha256).toBe(sha256(PDF_BYTES));
  });

  it('descarga el acta sellada (fallback remoto del CU-54)', async () => {
    const response = await request(app.getHttpServer()).get(
      `/certifications/hito/${hitoId}/acta`,
    );

    expect(response.status).toBe(200);
    expect(response.headers['content-type']).toContain('application/pdf');
    expect(Buffer.from(response.body).toString('utf8')).toContain('%%EOF');
  });

  it('hito sin acta → 404', async () => {
    const response = await request(app.getHttpServer()).get(
      '/certifications/hito/99999999-9999-4999-8999-999999999999',
    );

    expect(response.status).toBe(404);
  });
});
