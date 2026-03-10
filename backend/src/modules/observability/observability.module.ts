import { Module } from '@nestjs/common';
import { ObservabilityController } from './controller/observability.controller';
import { ObservabilityRepository } from './repository/observability.repository';
import { OtelInterceptor } from './service/otel.interceptor';
import { ObservabilityService } from './service/observability.service';

@Module({
  controllers: [ObservabilityController],
  providers: [ObservabilityRepository, ObservabilityService, OtelInterceptor],
  exports: [OtelInterceptor, ObservabilityService],
})
export class ObservabilityModule {}
