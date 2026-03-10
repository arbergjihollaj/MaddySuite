import { Module, forwardRef } from '@nestjs/common';
import { DevicesModule } from '@/modules/devices/devices.module';
import { TasksModule } from '@/modules/tasks/tasks.module';
import { SyncController } from './controller/sync.controller';
import { ChangesRepository } from './repository/changes.repository';
import { ClientMutationsRepository } from './repository/client-mutations.repository';
import { SyncCursorsRepository } from './repository/sync-cursors.repository';
import { ChangesService } from './service/changes.service';
import { SyncService } from './service/sync.service';

@Module({
  imports: [DevicesModule, forwardRef(() => TasksModule)],
  controllers: [SyncController],
  providers: [
    ChangesRepository,
    ClientMutationsRepository,
    SyncCursorsRepository,
    ChangesService,
    SyncService,
  ],
  exports: [ChangesService, SyncService, ChangesRepository],
})
export class SyncModule {}
