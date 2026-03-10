import { Injectable } from '@nestjs/common';
import { OutboxStatus } from '@prisma/client';
import { PrismaService } from '@/common/prisma/prisma.service';

@Injectable()
export class OutboxRepository {
  constructor(private readonly prisma: PrismaService) {}

  listPending(limit = 100) {
    return this.prisma.outboxEvent.findMany({
      where: {
        status: OutboxStatus.PENDING,
        availableAt: { lte: new Date() },
      },
      orderBy: [{ availableAt: 'asc' }],
      take: limit,
    });
  }

  markProcessing(id: bigint) {
    return this.prisma.outboxEvent.update({
      where: { id },
      data: { status: OutboxStatus.PROCESSING },
    });
  }

  markDone(id: bigint) {
    return this.prisma.outboxEvent.update({
      where: { id },
      data: { status: OutboxStatus.DONE },
    });
  }

  markFailed(id: bigint, retryInSeconds: number) {
    return this.prisma.outboxEvent.update({
      where: { id },
      data: {
        status: OutboxStatus.FAILED,
        attempts: { increment: 1 },
        availableAt: new Date(Date.now() + retryInSeconds * 1000),
      },
    });
  }
}
