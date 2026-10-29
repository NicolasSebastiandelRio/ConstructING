// Forzamos el modo test ANTES del bootstrap para usar better-sqlite3 en memoria.
process.env.NODE_ENV = 'test';

import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('CU-15 Establecer Ubicación Geográfica (E2E)', () => {
  let app: INestApplication;
  let workId: string;

  const propietarioEmail = 'propietario.cu15@gmail.com';

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

  it('registra al propietario (precondición)', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/register')
      .send({ nombre: 'Dueño', email: propietarioEmail, password: 'claveSegura1', role: 'Propietario' });
    expect(res.status).toBe(201);
  }, 20000);

  it('CU-15 paso 4: crea la obra con el ancla geográfica vinculada', async () => {
    const response = await request(app.getHttpServer())
      .post('/works')
      .send({
        nombre: 'Obra Geo',
        direccion: 'Av. Libertador 1234',
        fechaInicio: '2026-09-01',
        propietarioEmail,
        latitud: -34.6037,
        longitud: -58.3816,
      });

    expect(response.status).toBe(201);
    expect(response.body.latitud).toBeCloseTo(-34.6037);
    expect(response.body.longitud).toBeCloseTo(-58.3816);
    workId = response.body.id;
  });

  it('rechaza 400 una latitud fuera del rango geográfico', async () => {
    const response = await request(app.getHttpServer())
      .post('/works')
      .send({
        nombre: 'Obra Mala Lat',
        direccion: 'Calle 1',
        fechaInicio: '2026-09-01',
        propietarioEmail,
        latitud: 91,
      });

    expect(response.status).toBe(400);
  });

  it('rechaza 400 una longitud no numérica', async () => {
    const response = await request(app.getHttpServer())
      .post('/works')
      .send({
        nombre: 'Obra Mala Long',
        direccion: 'Calle 1',
        fechaInicio: '2026-09-01',
        propietarioEmail,
        longitud: 'oeste',
      });

    expect(response.status).toBe(400);
  });

  it('la edición de obra también puede fijar el ancla (precondición CU-15)', async () => {
    const create = await request(app.getHttpServer())
      .post('/works')
      .send({
        nombre: 'Obra Sin Geo',
        direccion: 'Calle 2',
        fechaInicio: '2026-09-01',
        propietarioEmail,
      });
    expect(create.status).toBe(201);

    const patch = await request(app.getHttpServer())
      .patch(`/works/${create.body.id}`)
      .send({ latitud: -31.4135, longitud: -64.181 });
    expect(patch.status).toBe(200);

    const check = await request(app.getHttpServer()).get(`/works/${create.body.id}`);
    expect(check.body.latitud).toBeCloseTo(-31.4135);
    expect(check.body.longitud).toBeCloseTo(-64.181);
    expect(workId).toBeDefined();
  });
});