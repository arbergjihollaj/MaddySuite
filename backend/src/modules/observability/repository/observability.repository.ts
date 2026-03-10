import { Injectable } from '@nestjs/common';

@Injectable()
export class ObservabilityRepository {
  capabilities() {
    return {
      structuredLogs: true,
      openTelemetry: true,
      requestIds: true,
    };
  }
}
