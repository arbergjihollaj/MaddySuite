import { Injectable } from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';

@Injectable()
export class HabitEntriesRepository {
  constructor(private readonly prisma: PrismaService) {}

  listByUser(userId: string) {
    return this.prisma.habitEntry.findMany({
      where: { userId },
      orderBy: [{ updatedAt: 'desc' }],
    });
  }
}
