import { Injectable } from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';

@Injectable()
export class SyncCursorsRepository {
  constructor(private readonly prisma: PrismaService) {}

  upsert(params: { userId: string; deviceId: string; cursor: bigint }) {
    return this.prisma.syncCursor.upsert({
      where: {
        userId_deviceId: {
          userId: params.userId,
          deviceId: params.deviceId,
        },
      },
      create: {
        userId: params.userId,
        deviceId: params.deviceId,
        cursor: params.cursor,
      },
      update: {
        cursor: params.cursor,
      },
    });
  }

  find(userId: string, deviceId: string) {
    return this.prisma.syncCursor.findUnique({
      where: {
        userId_deviceId: {
          userId,
          deviceId,
        },
      },
    });
  }
}
