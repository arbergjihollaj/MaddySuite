import { Injectable } from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';

@Injectable()
export class HabitsRepository {
  constructor(private readonly prisma: PrismaService) {}

  listByUser(userId: string) {
    return this.prisma.habit.findMany({
      where: { userId, deletedAt: null },
      orderBy: [{ updatedAt: 'desc' }],
    });
  }
}
