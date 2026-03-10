import { Injectable, LoggerService } from '@nestjs/common';
import pino from 'pino';
import { getRequestContext } from '../http/request-context';

@Injectable()
export class AppLoggerService implements LoggerService {
  private readonly logger = pino({
    level: process.env.NODE_ENV === 'production' ? 'info' : 'debug',
    base: {
      service: 'maddy-backend',
      env: process.env.NODE_ENV ?? 'development',
    },
  });

  log(message: string, context?: string): void {
    this.logger.info({ requestId: getRequestContext().requestId, context }, message);
  }

  error(message: string, trace?: string, context?: string): void {
    this.logger.error({ requestId: getRequestContext().requestId, trace, context }, message);
  }

  warn(message: string, context?: string): void {
    this.logger.warn({ requestId: getRequestContext().requestId, context }, message);
  }

  debug(message: string, context?: string): void {
    this.logger.debug({ requestId: getRequestContext().requestId, context }, message);
  }

  verbose(message: string, context?: string): void {
    this.logger.debug({ requestId: getRequestContext().requestId, context, verbose: true }, message);
  }
}
