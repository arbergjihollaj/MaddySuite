import { Injectable } from '@nestjs/common';
import { Prisma, Task } from '@prisma/client';
import { PrismaService } from '@/common/prisma/prisma.service';

@Injectable()
export class TasksRepository {
  constructor(private readonly prisma: PrismaService) {}

  listByUser(userId: string, includeDeleted = false): Promise<Task[]> {
    return this.prisma.task.findMany({
      where: {
        userId,
        ...(includeDeleted ? {} : { deletedAt: null }),
      },
      orderBy: [{ updatedAt: 'desc' }],
    });
  }

  findByIdForUser(id: string, userId: string): Promise<Task | null> {
    return this.prisma.task.findFirst({ where: { id, userId } });
  }

  create(data: Prisma.TaskUncheckedCreateInput): Promise<Task> {
    return this.prisma.task.create({ data });
  }

  update(id: string, userId: string, data: Prisma.TaskUncheckedUpdateInput): Promise<Task> {
    return this.prisma.task.update({
      where: { id },
      data,
    });
  }

  async upsertWithLww(input: {
    userId: string;
    id: string;
    data: Prisma.TaskUncheckedCreateInput;
    updateData: Prisma.TaskUncheckedUpdateInput;
    clientUpdatedAt: Date;
  }): Promise<{ task: Task; applied: boolean }> {
    const existing = await this.findByIdForUser(input.id, input.userId);

    if (!existing) {
      const created = await this.create(input.data);
      return { task: created, applied: true };
    }

    if (input.clientUpdatedAt < existing.clientUpdatedAt) {
      return { task: existing, applied: false };
    }

    const updated = await this.update(input.id, input.userId, input.updateData);
    return { task: updated, applied: true };
  }

  softDelete(id: string, userId: string, clientUpdatedAt: Date): Promise<Task> {
    return this.prisma.task.update({
      where: { id },
      data: {
        userId,
        status: 'DELETED',
        deletedAt: new Date(),
        clientUpdatedAt,
      },
    });
  }
}
