import { Injectable } from '@nestjs/common';
import { DevicePlatform } from '@prisma/client';
import { PrismaService } from '@/common/prisma/prisma.service';

@Injectable()
export class DevicesRepository {
  constructor(private readonly prisma: PrismaService) {}

  findByUserAndClientId(userId: string, clientDeviceId: string) {
    return this.prisma.device.findUnique({
      where: {
        userId_clientDeviceId: {
          userId,
          clientDeviceId,
        },
      },
    });
  }

  upsert(params: {
    userId: string;
    clientDeviceId: string;
    platform?: DevicePlatform;
    appVersion?: string;
  }) {
    return this.prisma.device.upsert({
      where: {
        userId_clientDeviceId: {
          userId: params.userId,
          clientDeviceId: params.clientDeviceId,
        },
      },
      create: {
        userId: params.userId,
        clientDeviceId: params.clientDeviceId,
        platform: params.platform ?? DevicePlatform.UNKNOWN,
        appVersion: params.appVersion,
        lastSeenAt: new Date(),
      },
      update: {
        platform: params.platform,
        appVersion: params.appVersion,
        lastSeenAt: new Date(),
      },
    });
  }
}
