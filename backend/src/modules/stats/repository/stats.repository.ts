import { Injectable } from '@nestjs/common';
import { TaskStatus } from '@prisma/client';
import { PrismaService } from '@/common/prisma/prisma.service';

@Injectable()
export class StatsRepository {
  constructor(private readonly prisma: PrismaService) {}

  async summary(userId: string) {
    const [openTasks, completedTasks, totalHabits, focusSessions, focusAggregate] = await Promise.all([
      this.prisma.task.count({
        where: {
          userId,
          deletedAt: null,
          status: {
            in: [TaskStatus.BACKLOG, TaskStatus.IN_PROGRESS, TaskStatus.MISSED],
          },
        },
      }),
      this.prisma.task.count({
        where: {
          userId,
          status: TaskStatus.DONE,
        },
      }),
      this.prisma.habit.count({ where: { userId, deletedAt: null } }),
      this.prisma.focusSession.count({ where: { userId, deletedAt: null } }),
      this.prisma.focusSession.aggregate({
        where: { userId, deletedAt: null },
        _sum: { durationMinutes: true },
      }),
    ]);

    return {
      openTasks,
      completedTasks,
      totalHabits,
      focusSessions,
      totalFocusMinutes: focusAggregate._sum.durationMinutes ?? 0,
    };
  }
}
