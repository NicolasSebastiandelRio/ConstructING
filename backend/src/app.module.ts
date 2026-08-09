import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from './auth/auth.module';
import { UserEntity } from './auth/user.entity';

@Module({
  imports: [
    // 1. Cargamos las variables de entorno globalmente (.env)
    ConfigModule.forRoot({ isGlobal: true }),
    
    // 2. Configuramos la conexión a Supabase (El "DataSource" faltante)
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => ({
        type: 'postgres',
        host: configService.get<string>('DB_HOST'),
        port: configService.get<number>('DB_PORT'),
        username: configService.get<string>('DB_USER'),
        password: configService.get<string>('DB_PASSWORD'),
        database: configService.get<string>('DB_NAME'),
        entities: [UserEntity],
        synchronize: true, // Sincroniza el DER con Supabase automáticamente
        ssl: { rejectUnauthorized: false }
      }),
    }),
    
    // 3. Importamos el módulo de identidad
    AuthModule,
  ],
})
export class AppModule {}