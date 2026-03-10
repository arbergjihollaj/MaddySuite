import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@/modules/auth/service/auth.guard';
import { EnqueueJobDto } from '../dto/enqueue-job.dto';
import { JobsService } from '../service/jobs.service';

@Controller('jobs')
@UseGuards(AuthGuard)
export class JobsController {
  constructor(private readonly jobsService: JobsService) {}

  @Post('enqueue')
  enqueue(@Body() dto: EnqueueJobDto) {
    return this.jobsService.enqueue(dto.name, dto.payload ?? {});
  }

  @Post('drain-outbox')
  drainOutbox() {
    return this.jobsService.processOutbox();
  }
}
