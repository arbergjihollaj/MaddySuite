import { Injectable, BadRequestException } from '@nestjs/common';
import { ChangeEntityType, Prisma } from '@prisma/client';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { DevicesService } from '@/modules/devices/service/devices.service';
import { TasksRepository } from '@/modules/tasks/repository/tasks.repository';
import { dtoToDifficulty, dtoToPriority, dtoToStatus, toTaskEntity } from '@/modules/tasks/service/tasks.mapper';
import { CreateTaskDto } from '@/modules/tasks/dto/create-task.dto';
import { ClientMutationsRepository } from '../repository/client-mutations.repository';
import { SyncCursorsRepository } from '../repository/sync-cursors.repository';
import { ChangesRepository } from '../repository/changes.repository';
import {
  SyncEntityTypeDto,
  SyncMutationOperationDto,
  SyncPushDto,
  SyncMutationDto,
} from '../dto/sync-push.dto';
import { SyncPullQueryDto } from '../dto/sync-pull.dto';
import { SyncAckDto } from '../dto/sync-ack.dto';

@Injectable()
export class SyncService {
  constructor(
    private readonly devicesService: DevicesService,
    private readonly tasksRepository: TasksRepository,
    private readonly changesRepository: ChangesRepository,
    private readonly clientMutationsRepository: ClientMutationsRepository,
    private readonly syncCursorsRepository: SyncCursorsRepository,
  ) {}

  async push(user: AuthenticatedUser, dto: SyncPushDto) {
    const clientDeviceId = this.requireClientDeviceId(dto.clientDeviceId);
    const device = await this.devicesService.register({
      userId: user.id,
      clientDeviceId,
      platform: undefined,
      appVersion: undefined,
    });

    const results: Array<Record<string, unknown>> = [];

    for (const mutation of dto.mutations) {
      const dedup = await this.clientMutationsRepository.find(
        user.id,
        device.id,
        mutation.clientMutationId,
      );

      if (dedup?.response) {
        results.push({
          clientMutationId: mutation.clientMutationId,
          duplicate: true,
          result: dedup.response,
        });
        continue;
      }

      const result = await this.applyMutation(user.id, device.id, mutation);

      await this.clientMutationsRepository.create({
        userId: user.id,
        deviceId: device.id,
        clientMutationId: mutation.clientMutationId,
        mutationType: `${mutation.entityType}:${mutation.operation}`,
        entityType: this.toEntityType(mutation.entityType),
        entityId: typeof result.entityId === 'string' ? result.entityId : undefined,
        response: result as Prisma.JsonObject,
      });

      results.push({
        clientMutationId: mutation.clientMutationId,
        duplicate: false,
        result,
      });
    }

    return {
      clientDeviceId,
      serverDeviceId: device.id,
      // Deprecated legacy alias. Use `clientDeviceId` instead.
      deviceId: clientDeviceId,
      accepted: dto.mutations.length,
      results,
      serverTimestamp: new Date().toISOString(),
    };
  }

  async pull(user: AuthenticatedUser, query: SyncPullQueryDto) {
    const cursor = this.parseCursor(query.cursor ?? '0', 'cursor');
    const limit = query.limit ?? 200;

    const changes = await this.changesRepository.pull(user.id, cursor, limit);

    const mapped = changes.map((change) => ({
      cursor: change.id.toString(),
      entityType: this.fromEntityType(change.entityType),
      entityId: change.entityId,
      operation: change.operation.toLowerCase(),
      occurredAt: change.occurredAt.toISOString(),
      payload: change.payload,
    }));

    const nextCursor = changes.length > 0 ? changes[changes.length - 1].id.toString() : cursor.toString();

    return {
      cursor: nextCursor,
      hasMore: changes.length === limit,
      changes: mapped,
    };
  }

  async ack(user: AuthenticatedUser, dto: SyncAckDto) {
    const clientDeviceId = this.requireClientDeviceId(dto.clientDeviceId);
    const device = await this.devicesService.register({
      userId: user.id,
      clientDeviceId,
      platform: undefined,
      appVersion: undefined,
    });

    const cursorValue = this.parseCursor(dto.cursor, 'cursor');
    const row = await this.syncCursorsRepository.upsert({
      userId: user.id,
      deviceId: device.id,
      cursor: cursorValue,
    });

    return {
      clientDeviceId,
      serverDeviceId: device.id,
      // Deprecated legacy alias. Use `clientDeviceId` instead.
      deviceId: clientDeviceId,
      cursor: row.cursor.toString(),
      updatedAt: row.updatedAt.toISOString(),
    };
  }

  private async applyMutation(userId: string, sourceDeviceId: string, mutation: SyncMutationDto) {
    if (mutation.entityType !== SyncEntityTypeDto.TASK) {
      return {
        status: 'skipped',
        reason: `Entity type ${mutation.entityType} not yet implemented`,
      };
    }

    if (mutation.operation === SyncMutationOperationDto.DELETE) {
      const entityId = mutation.entityId;
      if (!entityId) {
        throw new BadRequestException('entityId is required for delete operations');
      }

      const existing = await this.tasksRepository.findByIdForUser(entityId, userId);
      if (!existing) {
        return {
          status: 'noop',
          entityType: 'task',
          entityId,
          reason: 'Task not found',
        };
      }

      const deleted = await this.tasksRepository.softDelete(entityId, userId, new Date(mutation.timestamp));
      await this.changesRepository.append({
        userId,
        entityType: ChangeEntityType.TASK,
        entityId: deleted.id,
        operation: 'DELETED',
        payload: toTaskEntity(deleted) as Prisma.JsonObject,
        sourceDeviceId,
        sourceMutationId: mutation.clientMutationId,
      });

      return {
        status: 'applied',
        entityType: 'task',
        entityId: deleted.id,
        operation: 'delete',
        record: toTaskEntity(deleted),
      };
    }

    const payload = (mutation.payload ?? {}) as Partial<CreateTaskDto>;
    const id = mutation.entityId ?? payload.id;
    if (!id) {
      throw new BadRequestException('Task mutation requires entityId or payload.id');
    }

    if (payload.status === 'deleted') {
      throw new BadRequestException('Task delete must use operation=delete');
    }

    const clientUpdatedAt = new Date(mutation.timestamp);
    if (Number.isNaN(clientUpdatedAt.getTime())) {
      throw new BadRequestException('Invalid mutation timestamp');
    }

    const data = {
      id,
      userId,
      title: payload.title ?? '(untitled)',
      dueAt: payload.dueAt ? new Date(payload.dueAt) : null,
      tags: payload.tags ?? [],
      status: dtoToStatus(payload.status),
      difficulty: dtoToDifficulty(payload.difficulty),
      priority: dtoToPriority(payload.priority),
      mappedSkills: payload.mappedSkills ?? ['execution'],
      isDailyTask: payload.isDailyTask ?? false,
      isRequiredDailyTask: payload.isRequiredDailyTask ?? false,
      dailyDateKey: payload.dailyDateKey,
      completedAt: payload.completedAt ? new Date(payload.completedAt) : null,
      deletedAt: null,
      clientUpdatedAt,
      createdAt: new Date(),
      updatedAt: new Date(),
    };

    const updateData = {
      title: payload.title,
      dueAt: payload.dueAt ? new Date(payload.dueAt) : undefined,
      tags: payload.tags,
      status: payload.status ? dtoToStatus(payload.status) : undefined,
      difficulty: payload.difficulty ? dtoToDifficulty(payload.difficulty) : undefined,
      priority: payload.priority ? dtoToPriority(payload.priority) : undefined,
      mappedSkills: payload.mappedSkills,
      isDailyTask: payload.isDailyTask,
      isRequiredDailyTask: payload.isRequiredDailyTask,
      dailyDateKey: payload.dailyDateKey,
      completedAt: payload.completedAt ? new Date(payload.completedAt) : undefined,
      clientUpdatedAt,
      deletedAt: undefined,
    };

    const { task, applied, operation } = await this.tasksRepository.upsertWithLww({
      userId,
      id,
      data,
      updateData,
      clientUpdatedAt,
    });

    if (applied && operation) {
      await this.changesRepository.append({
        userId,
        entityType: ChangeEntityType.TASK,
        entityId: task.id,
        operation: operation === 'created' ? 'CREATED' : 'UPDATED',
        payload: toTaskEntity(task) as Prisma.JsonObject,
        sourceDeviceId,
        sourceMutationId: mutation.clientMutationId,
      });
    }

    return {
      status: applied ? 'applied' : 'ignored',
      entityType: 'task',
      entityId: task.id,
      operation: 'upsert',
      record: toTaskEntity(task),
      reason: applied ? undefined : 'Older client timestamp than server record',
    };
  }

  private parseCursor(raw: string, field: string): bigint {
    try {
      const parsed = BigInt(raw);
      if (parsed < 0n) {
        throw new Error(`${field} must be >= 0`);
      }
      return parsed;
    } catch {
      throw new BadRequestException(`Invalid ${field} value`);
    }
  }

  private requireClientDeviceId(value: string): string {
    const normalized = value.trim();
    if (normalized.length === 0) {
      throw new BadRequestException('clientDeviceId is required');
    }
    return normalized;
  }

  private toEntityType(entityType: SyncEntityTypeDto): ChangeEntityType | undefined {
    switch (entityType) {
      case SyncEntityTypeDto.TASK:
        return ChangeEntityType.TASK;
      case SyncEntityTypeDto.HABIT:
        return ChangeEntityType.HABIT;
      case SyncEntityTypeDto.HABIT_ENTRY:
        return ChangeEntityType.HABIT_ENTRY;
      case SyncEntityTypeDto.FOCUS_SESSION:
        return ChangeEntityType.FOCUS_SESSION;
      case SyncEntityTypeDto.SETTINGS:
        return ChangeEntityType.SETTINGS;
      case SyncEntityTypeDto.ATTACHMENT:
        return ChangeEntityType.ATTACHMENT;
      default:
        return undefined;
    }
  }

  private fromEntityType(entityType: ChangeEntityType): string {
    switch (entityType) {
      case ChangeEntityType.TASK:
        return 'task';
      case ChangeEntityType.HABIT:
        return 'habit';
      case ChangeEntityType.HABIT_ENTRY:
        return 'habit_entry';
      case ChangeEntityType.FOCUS_SESSION:
        return 'focus_session';
      case ChangeEntityType.SETTINGS:
        return 'settings';
      case ChangeEntityType.ATTACHMENT:
        return 'attachment';
      case ChangeEntityType.DEVICE:
        return 'device';
      default:
        return 'unknown';
    }
  }
}
