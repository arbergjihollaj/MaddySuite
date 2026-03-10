import { Module, forwardRef } from '@nestjs/common';
import { SyncModule } from '@/modules/sync/sync.module';
import { SettingsController } from './controller/settings.controller';
import { SettingsRepository } from './repository/settings.repository';
import { SettingsService } from './service/settings.service';

@Module({
  imports: [forwardRef(() => SyncModule)],
  controllers: [SettingsController],
  providers: [SettingsRepository, SettingsService],
  exports: [SettingsRepository, SettingsService],
})
export class SettingsModule {}
