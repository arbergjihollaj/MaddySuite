import { randomUUID } from 'crypto';
import { Injectable, NotFoundException } from '@nestjs/common';
import { TaskStatus } from '@prisma/client';
import { ChangesService } from '@/modules/sync/service/changes.service';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { CreateTaskDto } from '../dto/create-task.dto';
import { ListTasksQueryDto } from '../dto/list-tasks-query.dto';
import { UpdateTaskDto } from '../dto/update-task.dto';
import { TasksRepository } from '../repository/tasks.repository';
import { dtoToDifficulty, dtoToPriority, dtoToStatus, toTaskEntity } from './tasks.mapper';

@Injectable()
export class TasksService {
  constructor(
    private readonly tasksRepository: TasksRepository,
    private readonly changesService: ChangesService,
  ) {}

  async list(user: AuthenticatedUser, query: ListTasksQueryDto) {
    const tasks = await this.tasksRepository.listByUser(user.id, query.includeDeleted === true);
    return tasks.map(toTaskEntity);
  }

  async getById(user: AuthenticatedUser, id: string) {
    const task = await this.tasksRepository.findByIdForUser(id, user.id);
    if (!task) {
      throw new NotFoundException('Task not found');
    }
    return toTaskEntity(task);
  }

  async create(user: AuthenticatedUser, dto: CreateTaskDto) {
    const now = new Date();
    const id = dto.id ?? randomUUID();

    const created = await this.tasksRepository.create({
      id,
      userId: user.id,
      title: dto.title,
      dueAt: dto.dueAt ? new Date(dto.dueAt) : null,
      tags: dto.tags ?? [],
      status: dtoToStatus(dto.status),
      difficulty: dtoToDifficulty(dto.difficulty),
      priority: dtoToPriority(dto.priority),
      mappedSkills: dto.mappedSkills ?? ['execution'],
      isDailyTask: dto.isDailyTask ?? false,
      isRequiredDailyTask: dto.isRequiredDailyTask ?? false,
      dailyDateKey: dto.dailyDateKey,
      completedAt: dto.completedAt ? new Date(dto.completedAt) : null,
      clientUpdatedAt: dto.clientUpdatedAt ? new Date(dto.clientUpdatedAt) : now,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    });

    await this.changesService.recordTaskChange({
      userId: user.id,
      entityId: created.id,
      operation: 'CREATED',
      payload: toTaskEntity(created),
      sourceDeviceId: user.serverDeviceId ?? user.deviceId,
    });

    return toTaskEntity(created);
  }

  async update(user: AuthenticatedUser, id: string, dto: UpdateTaskDto) {
    const existing = await this.tasksRepository.findByIdForUser(id, user.id);
    if (!existing) {
      throw new NotFoundException('Task not found');
    }

    if (dto.status === 'deleted') {
      const deleted = await this.tasksRepository.softDelete(
        id,
        user.id,
        dto.clientUpdatedAt ? new Date(dto.clientUpdatedAt) : new Date(),
      );

      await this.changesService.recordTaskChange({
        userId: user.id,
        entityId: deleted.id,
        operation: 'DELETED',
        payload: toTaskEntity(deleted),
        sourceDeviceId: user.serverDeviceId ?? user.deviceId,
      });

      return toTaskEntity(deleted);
    }

    const updated = await this.tasksRepository.update(id, user.id, {
      title: dto.title,
      dueAt: dto.dueAt ? new Date(dto.dueAt) : undefined,
      tags: dto.tags,
      status: dto.status ? dtoToStatus(dto.status) : undefined,
      difficulty: dto.difficulty ? dtoToDifficulty(dto.difficulty) : undefined,
      priority: dto.priority ? dtoToPriority(dto.priority) : undefined,
      mappedSkills: dto.mappedSkills,
      isDailyTask: dto.isDailyTask,
      isRequiredDailyTask: dto.isRequiredDailyTask,
      dailyDateKey: dto.dailyDateKey,
      completedAt: dto.completedAt ? new Date(dto.completedAt) : undefined,
      clientUpdatedAt: dto.clientUpdatedAt ? new Date(dto.clientUpdatedAt) : new Date(),
      deletedAt: undefined,
    });

    await this.changesService.recordTaskChange({
      userId: user.id,
      entityId: updated.id,
      operation: updated.status === TaskStatus.DELETED ? 'DELETED' : 'UPDATED',
      payload: toTaskEntity(updated),
      sourceDeviceId: user.serverDeviceId ?? user.deviceId,
    });

    return toTaskEntity(updated);
  }

  async remove(user: AuthenticatedUser, id: string) {
    const existing = await this.tasksRepository.findByIdForUser(id, user.id);
    if (!existing) {
      throw new NotFoundException('Task not found');
    }

    const updated = await this.tasksRepository.softDelete(id, user.id, new Date());

    await this.changesService.recordTaskChange({
      userId: user.id,
      entityId: updated.id,
      operation: 'DELETED',
      payload: toTaskEntity(updated),
      sourceDeviceId: user.serverDeviceId ?? user.deviceId,
    });

    return { ok: true };
  }
}
