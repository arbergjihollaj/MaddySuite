import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { AppLoggerService } from './common/logger/app-logger.service';
import { getEnv } from './common/config/env';
import { JobsService } from './modules/jobs/service/jobs.service';

async function bootstrapWorker() {
  const env = getEnv();
  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: false,
  });

  const logger = app.get(AppLoggerService);
  app.useLogger(logger);

  app.get(JobsService);

  logger.log(`Worker started (pg-boss enabled=${env.PG_BOSS_ENABLED})`, 'WorkerBootstrap');
}

void bootstrapWorker();
