import { Controller, Get } from '@nestjs/common';
import { HealthService } from '../service/health.service';

@Controller()
export class HealthController {
  constructor(private readonly healthService: HealthService) {}

  @Get('health/live')
  live() {
    return this.healthService.liveness();
  }

  @Get('health/ready')
  ready() {
    return this.healthService.readiness();
  }

  @Get('version')
  version() {
    return this.healthService.version();
  }
}
