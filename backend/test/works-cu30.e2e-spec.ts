// Forzamos el modo test ANTES del bootstrap para usar better-sqlite3 en memoria.
process.env.NODE_ENV = 'test';

import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('CU-30 Recalcular Duración Total (E2E)', () => {
  let app: INestApplication;
  let workId: string;

  const propietarioEmail = 'propietario.cu30@gmail.com';

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

  it('registra profesional y propietario, y crea la obra sin fecha estimada', async () => {
    const profesional = await request(app.getHttpServer())
      .post('/auth/register')
      .send({ nombre: 'Ing. Pérez', email: 'profesional.cu30@gmail.com', password: 'claveSegura1', role: 'Profesional' });
    expect(profesional.status).toBe(201);

    const propietario = await request(app.getHttpServer())
      .post('/auth/register')
      .send({ nombre: 'Dueño', email: propietarioEmail, password: 'claveSegura1', role: 'Propietario' });
    expect(propietario.status).toBe(201);

    const obra = await request(app.getHttpServer())
      .post('/works')
      .send({
        nombre: 'Obra Planificada',
        direccion: 'Calle 123',
        fechaInicio: '2026-09-01',
        propietarioEmail,
      });
    expect(obra.status).toBe(201);
    expect(obra.body.fechaFinEstimada ?? null).toBeNull();
    workId = obra.body.id;
  }, 30000);

  it('PATCH persiste la fecha estimada y el GET la refleja (pasos 2-3)', async () => {
    const patch = await request(app.getHttpServer())
      .patch(`/works/${workId}`)
      .send({ fechaFinEstimada: '2026-09-23' });

    expect(patch.status).toBe(200);
    expect(patch.body.fechaFinEstimada).toBe('2026-09-23');

    const check = await request(app.getHttpServer()).get(`/works/${workId}`);
    expect(check.body.fechaFinEstimada).toBe('2026-09-23');
  });

  it('rechaza 400 una fecha estimada con formato inválido', async () => {
    const response = await request(app.getHttpServer())
      .patch(`/works/${workId}`)
      .send({ fechaFinEstimada: '23-09-2026' });

    expect(response.status).toBe(400);
  });
});