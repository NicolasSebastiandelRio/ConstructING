import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { CertificationEntity } from './certification.entity';
import { CertificationService } from './certification.service';
import { CertificationController } from './certification.controller';

/**
 * Módulo de Certificaciones (CU-59, PT-07): sellado criptográfico
 * inmutable del acta de conformidad (hash SHA-256 del PDF final).
 */
@Module({
  imports: [TypeOrmModule.forFeature([CertificationEntity])],
  controllers: [CertificationController],
  providers: [CertificationService],
})
export class CertificationsModule {}
