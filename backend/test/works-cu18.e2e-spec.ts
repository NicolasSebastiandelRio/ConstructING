// Forzamos el modo test ANTES del bootstrap para usar better-sqlite3 en memoria.
process.env.NODE_ENV = 'test';

import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('CU-18 Consultar Obras Asignadas (E2E)', () => {
  let app: INestApplication;
  let propietarioA: string;
  let propietarioB: string;
  let obraA1: string;

  const emailA = 'propietario.a@gmail.com';
  const emailB = 'propietario.b@gmail.com';

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

  it('registra profesional y dos propietarios, y crea 3 obras (precondición)', async () => {
    const profesional = await request(app.getHttpServer())
      .post('/auth/register')
      .send({ nombre: 'Ing. Pérez', email: 'profesional.cu18@gmail.com', password: 'claveSegura1', role: 'Profesional' });
    expect(profesional.status).toBe(201);

    for (const email of [emailA, emailB]) {
      const res = await request(app.getHttpServer())
        .post('/auth/register')
        .send({ nombre: 'Dueño', email, password: 'claveSegura1', role: 'Propietario' });
      expect(res.status).toBe(201);
      if (email === emailA) propietarioA = res.body.id;
      else propietarioB = res.body.id;
    }

    const obras = [
      { nombre: 'Obra A1', direccion: 'Calle A1', fechaInicio: '2026-09-01', propietarioEmail: emailA },
      { nombre: 'Obra A2', direccion: 'Calle A2', fechaInicio: '2026-09-01', propietarioEmail: emailA },
      { nombre: 'Obra B1', direccion: 'Calle B1', fechaInicio: '2026-09-01', propietarioEmail: emailB },
    ];
    for (const dto of obras) {
      const res = await request(app.getHttpServer()).post('/works').send(dto);
      expect(res.status).toBe(201);
      if (dto.nombre === 'Obra A1') obraA1 = res.body.id;
    }
  }, 45000);

  it('Flujo Normal: sin filtro devuelve el listado general (rol Profesional)', async () => {
    const response = await request(app.getHttpServer()).get('/works');

    expect(response.status).toBe(200);
    expect(response.body).toHaveLength(3);
  });

  it('"Mis Obras": con propietarioId sólo trae las obras de ese propietario', async () => {
    const deA = await request(app.getHttpServer()).get(`/works?propietarioId=${propietarioA}`);
    expect(deA.status).toBe(200);
    expect(deA.body).toHaveLength(2);
    for (const obra of deA.body) {
      expect(obra.propietarioId).toBe(propietarioA);
    }

    const deB = await request(app.getHttpServer()).get(`/works?propietarioId=${propietarioB}`);
    expect(deB.status).toBe(200);
    expect(deB.body).toHaveLength(1);
    expect(deB.body[0].nombre).toBe('Obra B1');
  });

  it('las archivadas quedan fuera del listado activo (CU-21)', async () => {
    // CU-21 Precondición: la obra debe completarse antes de archivarse.
    const completed = await request(app.getHttpServer())
      .patch(`/works/${obraA1}/status`)
      .send({ estado: 'Completado' });
    expect(completed.status).toBe(200);

    const archived = await request(app.getHttpServer()).delete(`/works/${obraA1}`);
    expect(archived.status).toBe(204);

    const deA = await request(app.getHttpServer()).get(`/works?propietarioId=${propietarioA}`);
    expect(deA.body).toHaveLength(1);
    expect(deA.body[0].nombre).toBe('Obra A2');

    const general = await request(app.getHttpServer()).get('/works');
    expect(general.body).toHaveLength(2);
  });
});