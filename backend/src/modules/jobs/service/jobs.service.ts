import { Inject, Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import PgBoss from 'pg-boss';
import type { Env } from '@/common/config/env';
import { AppLoggerService } from '@/common/logger/app-logger.service';
import { OutboxRepository } from '../repository/outbox.repository';

@Injectable()
export class JobsService implements OnModuleInit, OnModuleDestroy {
  private boss: PgBoss | null = null;

  constructor(
    @Inject('ENV') private readonly env: Env,
    private readonly logger: AppLoggerService,
    private readonly outboxRepository: OutboxRepository,
  ) {}

  async onModuleInit(): Promise<void> {
    if (!this.env.PG_BOSS_ENABLED) {
      this.logger.warn('pg-boss disabled by config', JobsService.name);
      return;
    }

    this.boss = new PgBoss({
      connectionString: this.env.DATABASE_URL,
      schema: this.env.PG_BOSS_SCHEMA,
    });

    await this.boss.start();

    await this.registerHandlers();
    await this.boss.schedule('maintenance.cleanup', '0 3 * * *', {});

    this.logger.log('pg-boss started', JobsService.name);
  }

  async onModuleDestroy(): Promise<void> {
    if (this.boss) {
      await this.boss.stop();
      this.logger.log('pg-boss stopped', JobsService.name);
    }
  }

  async enqueue(name: string, payload: Record<string, unknown> = {}) {
    if (!this.boss) {
      this.logger.warn(`enqueue(${name}) skipped, boss unavailable`, JobsService.name);
      return null;
    }

    return this.boss.send(name, payload);
  }

  async processOutbox(limit = 100) {
    const pending = await this.outboxRepository.listPending(limit);
    for (const event of pending) {
      await this.outboxRepository.markProcessing(event.id);
      try {
        await this.enqueue(String(event.topic), event.payload as Record<string, unknown>);
        await this.outboxRepository.markDone(event.id);
      } catch {
        await this.outboxRepository.markFailed(event.id, 60);
      }
    }

    return {
      processed: pending.length,
    };
  }

  private async registerHandlers() {
    if (!this.boss) return;

    await this.boss.work('maintenance.cleanup', async () => {
      this.logger.log('maintenance.cleanup executed', JobsService.name);
    });

    await this.boss.work('stats.aggregate', async () => {
      this.logger.log('stats.aggregate executed', JobsService.name);
    });

    await this.boss.work('notifications.dispatch', async () => {
      this.logger.log('notifications.dispatch executed', JobsService.name);
    });
  }
}
