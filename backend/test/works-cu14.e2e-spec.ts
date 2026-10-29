// Forzamos el modo test ANTES del bootstrap para usar better-sqlite3 en memoria.
process.env.NODE_ENV = 'test';

import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('CU-14 Vincular Propietario a Obra (E2E)', () => {
  let app: INestApplication;
  let workId: string;
  let segundoPropietarioId: string;

  const primerEmail = 'propietario.uno@gmail.com';
  const segundoEmail = 'propietario.dos@gmail.com';

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

  it('registra profesional y dos propietarios (precondición)', async () => {
    const profesional = await request(app.getHttpServer())
      .post('/auth/register')
      .send({ nombre: 'Ing. Pérez', email: 'profesional.cu14@gmail.com', password: 'claveSegura1', role: 'Profesional' });
    expect(profesional.status).toBe(201);

    for (const email of [primerEmail, segundoEmail]) {
      const res = await request(app.getHttpServer())
        .post('/auth/register')
        .send({ nombre: 'Dueño', email, password: 'claveSegura1', role: 'Propietario' });
      expect(res.status).toBe(201);
      if (email === segundoEmail) segundoPropietarioId = res.body.id;
    }
    expect(segundoPropietarioId).toBeDefined();
  }, 30000);

  it('CU-13: crea la obra vinculada al primer propietario', async () => {
    const response = await request(app.getHttpServer())
      .post('/works')
      .send({
        nombre: 'Obra Relink',
        direccion: 'Calle 123',
        fechaInicio: '2026-09-01',
        propietarioEmail: primerEmail,
      });

    expect(response.status).toBe(201);
    workId = response.body.id;
    expect(workId).toBeDefined();
  });

  it('CU-14 desde edición: PATCH con el correo del segundo propietario re-vincula la FK', async () => {
    const response = await request(app.getHttpServer())
      .patch(`/works/${workId}`)
      .send({ propietarioEmail: segundoEmail });

    expect(response.status).toBe(200);
    expect(response.body.propietarioId).toBe(segundoPropietarioId);
    expect(response.body).not.toHaveProperty('propietarioEmail');
  });

  it('CU-14 Alt. 2.1: PATCH con correo inexistente falla 400 sin modificar', async () => {
    const response = await request(app.getHttpServer())
      .patch(`/works/${workId}`)
      .send({ propietarioEmail: 'fantasma@gmail.com' });

    expect(response.status).toBe(400);

    const check = await request(app.getHttpServer()).get(`/works/${workId}`);
    expect(check.body.propietarioId).toBe(segundoPropietarioId);
  });

  it('PATCH con UUID inexistente también falla 400 (integridad RNF-D-03)', async () => {
    const response = await request(app.getHttpServer())
      .patch(`/works/${workId}`)
      .send({ propietarioId: '00000000-0000-4000-8000-000000000000' });

    expect(response.status).toBe(400);
  });
});