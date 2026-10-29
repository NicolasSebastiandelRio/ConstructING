// Forzamos el modo test ANTES del bootstrap para usar better-sqlite3 en memoria.
process.env.NODE_ENV = 'test';

import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('CU-60 Registrar Evento de Auditoría (E2E, PT-07)', () => {
  let app: INestApplication;

  const registro = {
    id: '11111111-1111-4111-8111-111111111111',
    usuarioId: '22222222-2222-4222-8222-222222222222',
    accion: 'hito_modificado',
    detalle: 'Cimientos: duración 3 → 5 días',
    obraId: '33333333-3333-4333-8333-333333333333',
    coordenadas: '-34.6037,-58.3816',
  };

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

  it('paso 2/4: inserta el registro inmutable con timestamp del servidor (201)', async () => {
    const response = await request(app.getHttpServer())
      .post('/audit-logs')
      .send(registro);

    expect(response.status).toBe(201);
    expect(response.body.id).toBe(registro.id);
    expect(response.body.usuarioId).toBe(registro.usuarioId);
    expect(response.body.accion).toBe(registro.accion);
    expect(response.body.detalle).toBe(registro.detalle);
    // Timestamp exacto emitido por el servidor.
    expect(new Date(response.body.createdAt).getTime()).not.toBeNaN();
  });

  it('falta el tipo de acción → 400', async () => {
    const response = await request(app.getHttpServer())
      .post('/audit-logs')
      .send({ id: '44444444-4444-4444-8444-444444444444', usuarioId: registro.usuarioId });

    expect(response.status).toBe(400);
  });

  it('falta el usuario → 400', async () => {
    const response = await request(app.getHttpServer())
      .post('/audit-logs')
      .send({ id: '44444444-4444-4444-8444-444444444444', accion: 'evidencia_cargada' });

    expect(response.status).toBe(400);
  });

  it('la huella es consultable por id (verificación de sello)', async () => {
    const response = await request(app.getHttpServer()).get(
      `/audit-logs/${registro.id}`,
    );

    expect(response.status).toBe(200);
    expect(response.body.accion).toBe(registro.accion);
  });

  it('registro inexistente → 404', async () => {
    const response = await request(app.getHttpServer()).get(
      '/audit-logs/99999999-9999-4999-8999-999999999999',
    );

    expect(response.status).toBe(404);
  });

  it('hoja forense: listado completo y por obra (insumo CU-63)', async () => {
    const all = await request(app.getHttpServer()).get('/audit-logs');
    expect(all.status).toBe(200);
    expect(Array.isArray(all.body)).toBe(true);
    expect(all.body.length).toBeGreaterThanOrEqual(1);

    const obra = await request(app.getHttpServer()).get(
      `/audit-logs/obra/${registro.obraId}`,
    );
    expect(obra.status).toBe(200);
    expect(obra.body.some((r: { id: string }) => r.id === registro.id)).toBe(true);
  });
});
