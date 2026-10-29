// Forzamos el modo test ANTES del bootstrap para usar better-sqlite3 en memoria.
process.env.NODE_ENV = 'test';

import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('CU-21 Archivar Obra (E2E)', () => {
  let app: INestApplication;
  let workId: string;

  const propietarioEmail = 'propietario.cu21@gmail.com';

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
      .send({ nombre: 'Ing. Pérez', email: 'profesional.cu21@gmail.com', password: 'claveSegura1', role: 'Profesional' });
    expect(profesional.status).toBe(201);

    const propietario = await request(app.getHttpServer())
      .post('/auth/register')
      .send({ nombre: 'Dueño', email: propietarioEmail, password: 'claveSegura1', role: 'Propietario' });
    expect(propietario.status).toBe(201);

    const obra = await request(app.getHttpServer())
      .post('/works')
      .send({
        nombre: 'Obra Archivable',
        direccion: 'Calle 123',
        fechaInicio: '2026-09-01',
        propietarioEmail,
      });
    expect(obra.status).toBe(201);
    workId = obra.body.id;
  }, 30000);

  it('Precondición: bloquea el archivado de una obra En Planificación (400)', async () => {
    const response = await request(app.getHttpServer()).delete(`/works/${workId}`);

    expect(response.status).toBe(400);
    expect(JSON.stringify(response.body)).toContain('Completado');
  });

  it('Precondición: bloquea el archivado de una obra En Ejecución (400)', async () => {
    const status = await request(app.getHttpServer())
      .patch(`/works/${workId}/status`)
      .send({ estado: 'En Ejecución' });
    expect(status.status).toBe(200);

    const response = await request(app.getHttpServer()).delete(`/works/${workId}`);
    expect(response.status).toBe(400);
  });

  it('Flujo Normal: archiva la obra completada (204)', async () => {
    const status = await request(app.getHttpServer())
      .patch(`/works/${workId}/status`)
      .send({ estado: 'Completado' });
    expect(status.status).toBe(200);

    const response = await request(app.getHttpServer()).delete(`/works/${workId}`);
    expect(response.status).toBe(204);
  });

  it('Paso 4: sale del listado activo y pasa al historial', async () => {
    const activas = await request(app.getHttpServer()).get('/works');
    expect(activas.body).toHaveLength(0);

    const historial = await request(app.getHttpServer()).get('/works?archived=true');
    expect(historial.status).toBe(200);
    expect(historial.body).toHaveLength(1);
    expect(historial.body[0].id).toBe(workId);
    expect(historial.body[0].estado).toBe('Archivado');
  });

  it('Poscondición: la ficha sigue visible pero la obra es inalterable', async () => {
    const ficha = await request(app.getHttpServer()).get(`/works/${workId}`);
    expect(ficha.status).toBe(200);

    const edit = await request(app.getHttpServer())
      .patch(`/works/${workId}`)
      .send({ nombre: 'Intento Tardío' });
    expect(edit.status).toBe(400);

    const secondArchive = await request(app.getHttpServer()).delete(`/works/${workId}`);
    expect(secondArchive.status).toBe(400);
  });
});