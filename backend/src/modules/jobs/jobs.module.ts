import { Module } from '@nestjs/common';
import { JobsController } from './controller/jobs.controller';
import { OutboxRepository } from './repository/outbox.repository';
import { JobsService } from './service/jobs.service';

@Module({
  controllers: [JobsController],
  providers: [OutboxRepository, JobsService],
  exports: [JobsService],
})
export class JobsModule {}
