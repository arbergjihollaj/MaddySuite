import { Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, Task, TaskStatus } from '@prisma/client';
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

  async update(id: string, userId: string, data: Prisma.TaskUncheckedUpdateInput): Promise<Task> {
    const updated = await this.prisma.task.updateMany({
      where: { id, userId },
      data,
    });

    if (updated.count === 0) {
      throw new NotFoundException('Task not found');
    }

    const row = await this.findByIdForUser(id, userId);
    if (!row) {
      throw new NotFoundException('Task not found');
    }

    return row;
  }

  async upsertWithLww(input: {
    userId: string;
    id: string;
    data: Prisma.TaskUncheckedCreateInput;
    updateData: Prisma.TaskUncheckedUpdateInput;
    clientUpdatedAt: Date;
  }): Promise<{ task: Task; applied: boolean; operation: 'created' | 'updated' | null }> {
    const existing = await this.findByIdForUser(input.id, input.userId);

    if (!existing) {
      const created = await this.create(input.data);
      return { task: created, applied: true, operation: 'created' };
    }

    if (input.clientUpdatedAt < existing.clientUpdatedAt) {
      return { task: existing, applied: false, operation: null };
    }

    const updated = await this.update(input.id, input.userId, input.updateData);
    return { task: updated, applied: true, operation: 'updated' };
  }

  async softDelete(id: string, userId: string, clientUpdatedAt: Date): Promise<Task> {
    const updated = await this.prisma.task.updateMany({
      where: { id, userId },
      data: {
        status: TaskStatus.DELETED,
        deletedAt: clientUpdatedAt,
        clientUpdatedAt,
      },
    });

    if (updated.count === 0) {
      throw new NotFoundException('Task not found');
    }

    const row = await this.findByIdForUser(id, userId);
    if (!row) {
      throw new NotFoundException('Task not found');
    }

    return row;
  }
}
