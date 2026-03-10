import { ChangeEntityType, ChangeOperation, Prisma } from '@prisma/client';
import { Injectable } from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';

@Injectable()
export class ChangesRepository {
  constructor(private readonly prisma: PrismaService) {}

  append(change: {
    userId: string;
    entityType: ChangeEntityType;
    entityId: string;
    operation: ChangeOperation;
    payload: Prisma.JsonObject;
    sourceDeviceId?: string;
    sourceMutationId?: string;
  }) {
    return this.prisma.change.create({
      data: {
        userId: change.userId,
        entityType: change.entityType,
        entityId: change.entityId,
        operation: change.operation,
        payload: change.payload,
        sourceDeviceId: change.sourceDeviceId,
        sourceMutationId: change.sourceMutationId,
      },
    });
  }

  pull(userId: string, cursor: bigint, limit: number) {
    return this.prisma.change.findMany({
      where: {
        userId,
        id: { gt: cursor },
      },
      orderBy: [{ id: 'asc' }],
      take: limit,
    });
  }
}
