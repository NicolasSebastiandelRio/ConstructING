// Forzamos el modo test ANTES del bootstrap para usar better-sqlite3 en memoria.
process.env.NODE_ENV = 'test';

import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('CU-17 Modificar Información de Obra (E2E)', () => {
  let app: INestApplication;
  let workId: string;

  const propietarioEmail = 'propietario.cu17@gmail.com';

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
      .send({ nombre: 'Ing. Pérez', email: 'profesional.cu17@gmail.com', password: 'claveSegura1', role: 'Profesional' });
    expect(profesional.status).toBe(201);

    const propietario = await request(app.getHttpServer())
      .post('/auth/register')
      .send({ nombre: 'Dueño', email: propietarioEmail, password: 'claveSegura1', role: 'Propietario' });
    expect(propietario.status).toBe(201);

    const obra = await request(app.getHttpServer())
      .post('/works')
      .send({
        nombre: 'Obra Editable',
        direccion: 'Calle 123',
        fechaInicio: '2026-09-01',
        propietarioEmail,
      });
    expect(obra.status).toBe(201);
    workId = obra.body.id;
  }, 30000);

  it('Flujo Normal: PATCH actualiza el registro y el GET lo refleja (refresca)', async () => {
    const patch = await request(app.getHttpServer())
      .patch(`/works/${workId}`)
      .send({ nombre: 'Obra Editada', direccion: 'Nueva Dirección 456' });

    expect(patch.status).toBe(200);
    expect(patch.body.nombre).toBe('Obra Editada');

    const check = await request(app.getHttpServer()).get(`/works/${workId}`);
    expect(check.body.nombre).toBe('Obra Editada');
    expect(check.body.direccion).toBe('Nueva Dirección 456');
  });

  it('CU-16 en edición: PATCH con nombre vacío falla 400', async () => {
    const response = await request(app.getHttpServer())
      .patch(`/works/${workId}`)
      .send({ nombre: '' });

    expect(response.status).toBe(400);
  });

  it('PATCH a una obra inexistente falla 404', async () => {
    const response = await request(app.getHttpServer())
      .patch('/works/00000000-0000-4000-8000-000000000000')
      .send({ nombre: 'X' });

    expect(response.status).toBe(404);
  });

  it('Precondición CU-17: archivada la obra, la edición se bloquea con 400', async () => {
    // CU-21 Precondición: la obra debe completarse antes de archivarse.
    const completed = await request(app.getHttpServer())
      .patch(`/works/${workId}/status`)
      .send({ estado: 'Completado' });
    expect(completed.status).toBe(200);

    const archived = await request(app.getHttpServer()).delete(`/works/${workId}`);
    expect(archived.status).toBe(204);

    // La ficha sigue visible en el historial (CU-21) pero inalterable.
    const ficha = await request(app.getHttpServer()).get(`/works/${workId}`);
    expect(ficha.status).toBe(200);

    const patch = await request(app.getHttpServer())
      .patch(`/works/${workId}`)
      .send({ nombre: 'Intento Tardío' });

    expect(patch.status).toBe(400);
    expect(JSON.stringify(patch.body)).toContain('archivada');

    const check = await request(app.getHttpServer()).get(`/works/${workId}`);
    expect(check.body.nombre).toBe('Obra Editada');
  });
});