// Forzamos el modo test ANTES del bootstrap para usar better-sqlite3 en memoria.
process.env.NODE_ENV = 'test';

import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('CU-22 Generar Código de Invitación (E2E)', () => {
  let app: INestApplication;
  let workId: string;
  let code: string;

  const propietarioEmail = 'propietario.cu22@gmail.com';
  const invitadoEmail = 'invitado.cu22@gmail.com';

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

  it('registra profesional y propietario, y crea la obra (precondición CU-14)', async () => {
    const profesional = await request(app.getHttpServer())
      .post('/auth/register')
      .send({ nombre: 'Ing. Pérez', email: 'profesional.cu22@gmail.com', password: 'claveSegura1', role: 'Profesional' });
    expect(profesional.status).toBe(201);

    const propietario = await request(app.getHttpServer())
      .post('/auth/register')
      .send({ nombre: 'Dueño', email: propietarioEmail, password: 'claveSegura1', role: 'Propietario' });
    expect(propietario.status).toBe(201);

    const obra = await request(app.getHttpServer())
      .post('/works')
      .send({
        nombre: 'Obra Con Invitación',
        direccion: 'Calle 123',
        fechaInicio: '2026-09-01',
        propietarioEmail,
      });
    expect(obra.status).toBe(201);
    workId = obra.body.id;
  }, 30000);

  it('CU-22 pasos 1-2: genera el código temporal asociado a la obra (201)', async () => {
    const response = await request(app.getHttpServer())
      .post(`/works/${workId}/invitations`)
      .send({ email: invitadoEmail });

    expect(response.status).toBe(201);
    expect(response.body.code).toMatch(/^CNG-[A-Z2-9]{6}$/);
    expect(response.body.email).toBe(invitadoEmail);
    // Pendiente = sin fecha de uso (NULL en BD, ausente en el JSON).
    expect(response.body.usedAt).toBeFalsy();
    code = response.body.code;
  });

  it('reutiliza la invitación pendiente en lugar de duplicarla', async () => {
    const response = await request(app.getHttpServer())
      .post(`/works/${workId}/invitations`)
      .send({ email: invitadoEmail });

    expect(response.status).toBe(201);
    expect(response.body.code).toBe(code);
  });

  it('rechaza 409 invitar a un correo ya registrado (CU-14 vincula directo)', async () => {
    const response = await request(app.getHttpServer())
      .post(`/works/${workId}/invitations`)
      .send({ email: propietarioEmail });

    expect(response.status).toBe(409);
  });

  it('resuelve el código antes del registro (200) y falla 404 con otro', async () => {
    const ok = await request(app.getHttpServer()).get(`/works/invitations/${code}`);
    expect(ok.status).toBe(200);
    expect(ok.body.workId).toBe(workId);
    expect(ok.body.email).toBe(invitadoEmail);

    const missing = await request(app.getHttpServer()).get('/works/invitations/CNG-XXXXXX');
    expect(missing.status).toBe(404);
  });

  it('CU-06/CU-22 poscondición: el registro con el código vincula la obra', async () => {
    const register = await request(app.getHttpServer())
      .post('/auth/register')
      .send({
        nombre: 'Invitado Nuevo',
        email: invitadoEmail,
        password: 'claveSegura1',
        role: 'Propietario',
        invitationCode: code,
      });

    expect(register.status).toBe(201);
    const newUserId = register.body.id;
    expect(newUserId).toBeDefined();

    const obra = await request(app.getHttpServer()).get(`/works/${workId}`);
    expect(obra.body.propietarioId).toBe(newUserId);

    // El código queda usado: ya no se puede resolver ni reclamar (410 Gone).
    const reused = await request(app.getHttpServer()).get(`/works/invitations/${code}`);
    expect(reused.status).toBe(410);
  }, 20000);

  it('rechaza reclamar el código usado con otro correo (410)', async () => {
    const response = await request(app.getHttpServer())
      .post('/auth/register')
      .send({
        nombre: 'Otro',
        email: 'otro.cu22@gmail.com',
        password: 'claveSegura1',
        role: 'Propietario',
        invitationCode: code,
      });

    expect(response.status).toBe(410);
  }, 20000);
});