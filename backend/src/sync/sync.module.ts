import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MilestoneSyncEntity } from './milestone-sync.entity';
import { EvidenceSyncEntity } from './evidence-sync.entity';
import { MilestoneSyncService } from './milestone-sync.service';
import { EvidenceSyncService } from './evidence-sync.service';
import { SyncController } from './sync.controller';

/**
 * Motor de sincronización offline-first (CU-44 al CU-47, PT-06).
 *
 * Recibe el volcado de registros pendientes del dispositivo: hitos
 * (CU-44/CU-47) y evidencias periciales (CU-44/CU-45/CU-46).
 */
@Module({
  imports: [TypeOrmModule.forFeature([MilestoneSyncEntity, EvidenceSyncEntity])],
  controllers: [SyncController],
  providers: [MilestoneSyncService, EvidenceSyncService],
  exports: [MilestoneSyncService, EvidenceSyncService],
})
export class SyncModule {}
