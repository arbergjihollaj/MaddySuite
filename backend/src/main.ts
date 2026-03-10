import 'reflect-metadata';
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import fastifyHelmet from '@fastify/helmet';
import fastifySensible from '@fastify/sensible';
import { AppModule } from './app.module';
import { getEnv } from './common/config/env';
import { AppLoggerService } from './common/logger/app-logger.service';

async function bootstrap() {
  const env = getEnv();
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    new FastifyAdapter({
      logger: false,
    }),
    { bufferLogs: true },
  );

  const logger = app.get(AppLoggerService);
  app.useLogger(logger);

  await app.register(fastifyHelmet);
  await app.register(fastifySensible);

  app.setGlobalPrefix(env.API_PREFIX);
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
      transformOptions: { enableImplicitConversion: true },
    }),
  );

  const swaggerConfig = new DocumentBuilder()
    .setTitle('Maddy Backend API')
    .setDescription('Offline-first sync backend for Maddy iPhone + macOS apps')
    .setVersion(env.APP_VERSION)
    .addBearerAuth()
    .build();

  const swaggerDoc = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup(`${env.API_PREFIX}/docs`, app, swaggerDoc, {
    customSiteTitle: 'Maddy Backend API Docs',
  });

  await app.listen({ port: env.PORT, host: '0.0.0.0' });

  logger.log(`API listening on :${env.PORT}`, 'Bootstrap');
}

void bootstrap();
