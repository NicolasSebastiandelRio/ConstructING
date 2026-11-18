import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('WorksModule & Relational Integrity (E2E - QA-03)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(new ValidationPipe());
    await app.init();
  }, 15000); // <- Extendemos el timeout a 15 segundos para el arranque de la app

  afterAll(async () => {
    if (app) {
      await app.close();
    }
  });

  it('/works (POST) - Debe fallar (400) si el propietarioId no existe (RNF-D-03)', async () => {
    const invalidWork = {
      nombre: 'Obra Test Huérfana',
      direccion: 'Calle Falsa 123',
      fechaInicio: '2026-08-20',
      propietarioId: '00000000-0000-0000-0000-000000000000',
    };

    const response = await request(app.getHttpServer())
      .post('/works')
      .send(invalidWork);

    expect(response.status).toBe(400);
  });
});