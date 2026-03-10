import { randomUUID } from 'crypto';
import { Injectable, NestMiddleware } from '@nestjs/common';
import { FastifyReply, FastifyRequest } from 'fastify';
import { withRequestContext } from './request-context';

@Injectable()
export class RequestIdMiddleware implements NestMiddleware {
  use(req: FastifyRequest, res: FastifyReply, next: () => void): void {
    const header = req.headers['x-request-id'];
    const requestId = typeof header === 'string' && header.length > 0 ? header : randomUUID();

    req.headers['x-request-id'] = requestId;
    res.header('x-request-id', requestId);

    withRequestContext(requestId, () => next());
  }
}
