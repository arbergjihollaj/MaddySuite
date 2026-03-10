import { Module } from '@nestjs/common';
import { HealthController } from './controller/health.controller';
import { HealthRepository } from './repository/health.repository';
import { HealthService } from './service/health.service';

@Module({
  controllers: [HealthController],
  providers: [HealthRepository, HealthService],
  exports: [HealthService],
})
export class HealthModule {}
