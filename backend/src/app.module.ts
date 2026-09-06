import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { UsersModule } from './users/users.module';
import { WorksModule } from './works/works.module';
import { AuthModule } from './auth/auth.module'; // <- Importar AuthModule  
import { UserEntity } from './auth/user.entity';
import { WorkEntity } from './works/entities/work.entity';
import { WorkInvitationEntity } from './works/entities/work-invitation.entity';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
    }),
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (configService: ConfigService): any => {
        const isTest = process.env.NODE_ENV === 'test';

        if (isTest) {
          // Configuración ultrarrápida y aislada en memoria para pruebas E2E (QA-03)
          return {
            type: 'better-sqlite3', // <- Usamos el driver oficial soportado por TypeORM 0.3.x
            database: ':memory:',
            entities: [UserEntity, WorkEntity, WorkInvitationEntity],
            synchronize: true,
            dropSchema: true,
          };
        }

        // Configuración oficial en PostgreSQL para Desarrollo y Producción (RNF-D-03)
        // DB_SSL=true es necesario para Postgres administrados (Supabase, Neon, AWS RDS).
        return {
          type: 'postgres',
          host: configService.get<string>('DB_HOST', 'localhost'),
          port: configService.get<number>('DB_PORT', 5432),
          username: configService.get<string>('DB_USER', 'postgres'),
          password: configService.get<string>('DB_PASSWORD', 'postgres'),
          database: configService.get<string>('DB_NAME', 'constructingsal'),
          entities: [UserEntity, WorkEntity, WorkInvitationEntity],
          synchronize: true,
          ssl:
            configService.get<string>('DB_SSL', 'false') === 'true'
              ? { rejectUnauthorized: false }
              : undefined,
        };
      },
    }),
    UsersModule,
    WorksModule,
    AuthModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}