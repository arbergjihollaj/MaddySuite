import { Controller, Get } from '@nestjs/common';
import { ObservabilityService } from '../service/observability.service';

@Controller('observability')
export class ObservabilityController {
  constructor(private readonly observabilityService: ObservabilityService) {}

  @Get()
  getInfo() {
    return this.observabilityService.info();
  }
}
