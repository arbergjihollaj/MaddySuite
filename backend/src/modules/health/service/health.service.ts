import { Inject, Injectable } from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';
import type { Env } from '@/common/config/env';

@Injectable()
export class HealthService {
  constructor(
    private readonly prisma: PrismaService,
    @Inject('ENV') private readonly env: Env,
  ) {}

  liveness() {
    return {
      status: 'ok',
      service: this.env.APP_NAME,
      timestamp: new Date().toISOString(),
    };
  }

  async readiness() {
    await this.prisma.$queryRaw`SELECT 1`;

    return {
      status: 'ready',
      checks: {
        database: 'ok',
      },
      timestamp: new Date().toISOString(),
    };
  }

  version() {
    return {
      name: this.env.APP_NAME,
      version: this.env.APP_VERSION,
      gitSha: this.env.GIT_SHA,
      nodeEnv: this.env.NODE_ENV,
    };
  }
}
