import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { json, urlencoded } from 'express';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // CU-46: los chunks base64 de las evidencias (≈512 KB → ~700 KB en
  // base64, y videos de hasta 15 MB reensamblados por bloques) superan el
  // límite por defecto de Express (100 KB), que devolvía HTTP 413 y hacía
  // que ninguna imagen se sincronizara. Se amplia al límite del CU-38.
  app.use(json({ limit: '50mb' }));
  app.use(urlencoded({ extended: true, limit: '50mb' }));

  // ValidationPipe global: garantiza el formato de los datos de entrada
  // (CU-07 Paso 4 "Valida el formato de los nuevos datos ingresados") y
  // descarta campos no declarados en los DTOs.
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
    }),
  );

  app.enableCors({
    origin: '*', // En entorno de desarrollo permitimos cualquier origen local
    methods: 'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS',
    credentials: true,
  });

  await app.listen(process.env.PORT ?? 3000);
}
bootstrap();
