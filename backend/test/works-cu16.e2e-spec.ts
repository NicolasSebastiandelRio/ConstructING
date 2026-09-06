// Forzamos el modo test ANTES del bootstrap para usar better-sqlite3 en memoria.
process.env.NODE_ENV = 'test';

import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('CU-16 Validar Datos Obligatorios (E2E)', () => {
  let app: INestApplication;

  const propietarioEmail = 'propietario.cu16@gmail.com';
  const base = {
    nombre: 'Obra Válida',
    direccion: 'Av. Libertador 1234',
    fechaInicio: '2026-09-01',
    propietarioEmail,
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

  it('registra al propietario (precondición)', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/register')
      .send({ nombre: 'Dueño', email: propietarioEmail, password: 'claveSegura1', role: 'Propietario' });
    expect(res.status).toBe(201);
  }, 20000);

  it('Flujo Normal: payload completo retorna validación exitosa y persiste (201)', async () => {
    const response = await request(app.getHttpServer()).post('/works').send(base);

    expect(response.status).toBe(201);
    expect(response.body.id).toBeDefined();
  });

  it('Alt. 2.1/2.2: nombre vacío retorna error (400)', async () => {
    const response = await request(app.getHttpServer())
      .post('/works')
      .send({ ...base, nombre: '' });

    expect(response.status).toBe(400);
    expect(JSON.stringify(response.body)).toContain('nombre');
  });

  it('Alt. 2.1/2.2: dirección ausente retorna error (400)', async () => {
    const { direccion, ...sinDireccion } = base;
    void direccion;
    const response = await request(app.getHttpServer()).post('/works').send(sinDireccion);

    expect(response.status).toBe(400);
  });

  it('Alt. 2.1/2.2: fecha con formato inválido retorna error (400)', async () => {
    const response = await request(app.getHttpServer())
      .post('/works')
      .send({ ...base, fechaInicio: '01-09-2026' });

    expect(response.status).toBe(400);
  });

  it('Alt. 2.1/2.2: correo de propietario con formato inválido retorna error (400)', async () => {
    const response = await request(app.getHttpServer())
      .post('/works')
      .send({ ...base, propietarioEmail: 'no-es-un-correo' });

    expect(response.status).toBe(400);
  });
});