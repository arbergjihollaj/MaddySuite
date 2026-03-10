import { Inject, Injectable } from '@nestjs/common';
import type { Env } from '@/common/config/env';
import { ObservabilityRepository } from '../repository/observability.repository';

@Injectable()
export class ObservabilityService {
  constructor(
    @Inject('ENV') private readonly env: Env,
    private readonly repository: ObservabilityRepository,
  ) {}

  info() {
    return {
      ...this.repository.capabilities(),
      otelEnabled: this.env.OTEL_ENABLED,
      otelServiceName: this.env.OTEL_SERVICE_NAME,
    };
  }
}
