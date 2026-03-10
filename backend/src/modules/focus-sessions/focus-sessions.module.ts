import { Module } from '@nestjs/common';
import { FocusSessionsController } from './controller/focus-sessions.controller';
import { FocusSessionsRepository } from './repository/focus-sessions.repository';
import { FocusSessionsService } from './service/focus-sessions.service';

@Module({
  controllers: [FocusSessionsController],
  providers: [FocusSessionsRepository, FocusSessionsService],
  exports: [FocusSessionsRepository, FocusSessionsService],
})
export class FocusSessionsModule {}
