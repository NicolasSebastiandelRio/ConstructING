import { Test, TestingModule } from '@nestjs/testing';
import { AppController } from './app.controller';
import { AppService } from './app.service';

describe('AppController', () => {
  let appController: AppController;

  beforeEach(async () => {
    const app: TestingModule = await Test.createTestingModule({
      controllers: [AppController],
      providers: [AppService],
    }).compile();

    appController = app.get<AppController>(AppController);
  });

  describe('root', () => {
    it('should return "Hello World!"', () => {
      expect(appController.getHello()).toBe('Hello World!');
    });
  });

  describe('health (CU-43 heartbeat)', () => {
    it('responde ok con timestamp', () => {
      const result = appController.health();

      expect(result.status).toBe('ok');
      expect(Date.parse(result.timestamp)).not.toBeNaN();
    });
  });
});
