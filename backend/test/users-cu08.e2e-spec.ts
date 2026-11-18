// Forzamos el modo test ANTES del bootstrap para usar better-sqlite3 en memoria.
process.env.NODE_ENV = 'test';

import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('CU-08 Dar de baja / Inhabilitar + CU-09 Listado (E2E)', () => {
  let app: INestApplication;
  let userId: string;

  const email = 'ana.inhabilitar@gmail.com';
  const password = 'claveSegura1';

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

  it('registra un usuario activo (CU-06)', async () => {
    const response = await request(app.getHttpServer())
      .post('/auth/register')
      .send({ nombre: 'Ana García', email, password, role: 'Propietario' });

    expect(response.status).toBe(201);
    expect(response.body.email).toBe(email);
    userId = response.body.id;
    expect(userId).toBeDefined();
  });

  it('CU-09: el listado incluye al usuario como Activo (deletedAt nulo)', async () => {
    const response = await request(app.getHttpServer()).get('/users');

    expect(response.status).toBe(200);
    const user = (response.body as unknown[]).find(
      (u) => (u as { email: string }).email === email,
    ) as { deletedAt: string | null };
    expect(user).toBeDefined();
    expect(user.deletedAt).toBeNull();
  });

  it('CU-08: inhabilita al usuario (soft-delete, 204)', async () => {
    const response = await request(app.getHttpServer()).delete(`/users/${userId}`);

    expect(response.status).toBe(204);
  });

  it('CU-09: el listado conserva al usuario pero marcado como inactivo', async () => {
    const response = await request(app.getHttpServer()).get('/users');

    expect(response.status).toBe(200);
    const user = (response.body as unknown[]).find(
      (u) => (u as { email: string }).email === email,
    ) as { deletedAt: string | null };
    expect(user).toBeDefined();
    expect(user.deletedAt).not.toBeNull();
  });

  it('CU-08 Poscondición: el usuario inhabilitado NO supera el login (401)', async () => {
    const response = await request(app.getHttpServer())
      .post('/auth/login')
      .send({ email, password });

    expect(response.status).toBe(401);
  });

  it('CU-08 (habilitar): restaura al usuario y vuelve a estar activo', async () => {
    const response = await request(app.getHttpServer()).post(`/users/${userId}/restore`);

    expect(response.status).toBe(200);
    expect(response.body.deletedAt).toBeNull();
    expect(response.body).not.toHaveProperty('passwordHash');
  });

  it('el usuario habilitado vuelve a superar el login (200 + JWT)', async () => {
    const response = await request(app.getHttpServer())
      .post('/auth/login')
      .send({ email, password });

    expect(response.status).toBe(200);
    expect(response.body.access_token).toBeDefined();
  });
});