// Forzamos el modo test ANTES del bootstrap para usar better-sqlite3 en memoria.
process.env.NODE_ENV = 'test';

import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('CU-20 Actualizar Estado del Proyecto (E2E)', () => {
  let app: INestApplication;
  let workId: string;

  const propietarioEmail = 'propietario.cu20@gmail.com';

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

  it('registra profesional y propietario, y crea la obra (precondición)', async () => {
    const profesional = await request(app.getHttpServer())
      .post('/auth/register')
      .send({ nombre: 'Ing. Pérez', email: 'profesional.cu20@gmail.com', password: 'claveSegura1', role: 'Profesional' });
    expect(profesional.status).toBe(201);

    const propietario = await request(app.getHttpServer())
      .post('/auth/register')
      .send({ nombre: 'Dueño', email: propietarioEmail, password: 'claveSegura1', role: 'Propietario' });
    expect(propietario.status).toBe(201);

    const obra = await request(app.getHttpServer())
      .post('/works')
      .send({
        nombre: 'Obra Faseable',
        direccion: 'Calle 123',
        fechaInicio: '2026-09-01',
        propietarioEmail,
      });
    expect(obra.status).toBe(201);
    expect(obra.body.estado).toBe('En Planificación');
    workId = obra.body.id;
  }, 30000);

  it('Flujo Normal: cambia la fase y el GET la refleja para todos', async () => {
    const patch = await request(app.getHttpServer())
      .patch(`/works/${workId}/status`)
      .send({ estado: 'En Ejecución' });

    expect(patch.status).toBe(200);
    expect(patch.body.estado).toBe('En Ejecución');

    const check = await request(app.getHttpServer()).get(`/works/${workId}`);
    expect(check.body.estado).toBe('En Ejecución');
  });

  it('avanza a Completado (fase válida del enum)', async () => {
    const patch = await request(app.getHttpServer())
      .patch(`/works/${workId}/status`)
      .send({ estado: 'Completado' });

    expect(patch.status).toBe(200);
    expect(patch.body.estado).toBe('Completado');
  });

  it('rechaza 400 un estado fuera del enum', async () => {
    const response = await request(app.getHttpServer())
      .patch(`/works/${workId}/status`)
      .send({ estado: 'En Otro Lado' });

    expect(response.status).toBe(400);
  });

  it('rechaza 400 el archivado directo (pertenece a CU-21)', async () => {
    const response = await request(app.getHttpServer())
      .patch(`/works/${workId}/status`)
      .send({ estado: 'Archivado' });

    expect(response.status).toBe(400);
  });

  it('bloquea el cambio de estado de una obra archivada', async () => {
    const archived = await request(app.getHttpServer()).delete(`/works/${workId}`);
    expect(archived.status).toBe(204);

    const patch = await request(app.getHttpServer())
      .patch(`/works/${workId}/status`)
      .send({ estado: 'En Ejecución' });

    expect(patch.status).toBe(400);
  });
});