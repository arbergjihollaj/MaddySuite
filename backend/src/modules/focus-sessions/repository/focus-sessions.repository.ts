import { Injectable } from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';

@Injectable()
export class FocusSessionsRepository {
  constructor(private readonly prisma: PrismaService) {}

  listByUser(userId: string) {
    return this.prisma.focusSession.findMany({
      where: { userId, deletedAt: null },
      orderBy: [{ startAt: 'desc' }],
    });
  }
}
