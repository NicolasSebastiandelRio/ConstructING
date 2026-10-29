// Forzamos el modo test ANTES del bootstrap para usar better-sqlite3 en memoria.
process.env.NODE_ENV = 'test';

import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('CU-13 Crear Nueva Obra + CU-14 Vincular Propietario (E2E)', () => {
  let app: INestApplication;
  let propietarioId: string;

  const propietarioEmail = 'propietario.obra@gmail.com';

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

  it('registra al profesional y al propietario (precondición CU-13)', async () => {
    const profesional = await request(app.getHttpServer())
      .post('/auth/register')
      .send({ nombre: 'Ing. Pérez', email: 'profesional.obra@gmail.com', password: 'claveSegura1', role: 'Profesional' });
    expect(profesional.status).toBe(201);

    const propietario = await request(app.getHttpServer())
      .post('/auth/register')
      .send({ nombre: 'Dueño López', email: propietarioEmail, password: 'claveSegura1', role: 'Propietario' });
    expect(propietario.status).toBe(201);
    propietarioId = propietario.body.id;
    expect(propietarioId).toBeDefined();
  }, 25000);

  it('CU-13: crea la obra vinculando al propietario por correo (201 + En Planificación)', async () => {
    const response = await request(app.getHttpServer())
      .post('/works')
      .send({
        nombre: 'Edificio Central',
        direccion: 'Av. Libertador 1234',
        fechaInicio: '2026-09-01',
        descripcion: 'Torre residencial',
        propietarioEmail,
      });

    expect(response.status).toBe(201);
    expect(response.body.nombre).toBe('Edificio Central');
    expect(response.body.estado).toBe('En Planificación');
    expect(response.body.propietarioId).toBe(propietarioId);
  });

  it('CU-14 Alt. 2.1: falla 400 si el correo del propietario no existe', async () => {
    const response = await request(app.getHttpServer())
      .post('/works')
      .send({
        nombre: 'Obra Huérfana',
        direccion: 'Calle Falsa 123',
        fechaInicio: '2026-09-01',
        propietarioEmail: 'fantasma@gmail.com',
      });

    expect(response.status).toBe(400);
  });

  it('falla 400 si no se informa ningún identificador de propietario', async () => {
    const response = await request(app.getHttpServer())
      .post('/works')
      .send({
        nombre: 'Obra Sin Dueño',
        direccion: 'Calle Falsa 123',
        fechaInicio: '2026-09-01',
      });

    expect(response.status).toBe(400);
  });
});