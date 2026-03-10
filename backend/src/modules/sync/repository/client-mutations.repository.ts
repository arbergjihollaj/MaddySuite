import { Injectable } from '@nestjs/common';
import { ChangeEntityType, Prisma } from '@prisma/client';
import { PrismaService } from '@/common/prisma/prisma.service';

@Injectable()
export class ClientMutationsRepository {
  constructor(private readonly prisma: PrismaService) {}

  find(userId: string, deviceId: string, clientMutationId: string) {
    return this.prisma.clientMutation.findUnique({
      where: {
        userId_deviceId_clientMutationId: {
          userId,
          deviceId,
          clientMutationId,
        },
      },
    });
  }

  create(params: {
    userId: string;
    deviceId: string;
    clientMutationId: string;
    mutationType: string;
    entityType?: ChangeEntityType;
    entityId?: string;
    response?: Prisma.JsonObject;
  }) {
    return this.prisma.clientMutation.create({
      data: {
        userId: params.userId,
        deviceId: params.deviceId,
        clientMutationId: params.clientMutationId,
        mutationType: params.mutationType,
        entityType: params.entityType,
        entityId: params.entityId,
        response: params.response,
      },
    });
  }
}
