import { Injectable } from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';

@Injectable()
export class SettingsRepository {
  constructor(private readonly prisma: PrismaService) {}

  getByUser(userId: string) {
    return this.prisma.setting.findUnique({ where: { userId } });
  }

  upsert(userId: string, payload: Record<string, unknown>, clientUpdatedAt: Date) {
    return this.prisma.setting.upsert({
      where: { userId },
      create: {
        userId,
        payload,
        clientUpdatedAt,
      },
      update: {
        payload,
        clientUpdatedAt,
      },
    });
  }
}
