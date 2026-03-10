import { Module, forwardRef } from '@nestjs/common';
import { SyncModule } from '@/modules/sync/sync.module';
import { TasksController } from './controller/tasks.controller';
import { TasksRepository } from './repository/tasks.repository';
import { TasksService } from './service/tasks.service';

@Module({
  imports: [forwardRef(() => SyncModule)],
  controllers: [TasksController],
  providers: [TasksRepository, TasksService],
  exports: [TasksRepository, TasksService],
})
export class TasksModule {}
