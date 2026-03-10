import { BadRequestException } from '@nestjs/common';
import { ChangeEntityType, ChangeOperation, TaskDifficulty, TaskPriority, TaskStatus } from '@prisma/client';
import { SyncAckDto } from '../src/modules/sync/dto/sync-ack.dto';
import { SyncEntityTypeDto, SyncMutationOperationDto } from '../src/modules/sync/dto/sync-push.dto';
import { SyncService } from '../src/modules/sync/service/sync.service';

function makeTask(id: string) {
  const now = new Date('2026-03-10T00:00:00.000Z');
  return {
    id,
    userId: '00000000-0000-0000-0000-000000000001',
    title: 'Task',
    dueAt: null,
    tags: [],
    status: TaskStatus.BACKLOG,
    difficulty: TaskDifficulty.MEDIUM,
    priority: TaskPriority.MEDIUM,
    mappedSkills: ['execution'],
    isDailyTask: false,
    isRequiredDailyTask: false,
    dailyDateKey: null,
    completedAt: null,
    deletedAt: null,
    clientUpdatedAt: now,
    createdAt: now,
    updatedAt: now,
  };
}

function makeService(overrides?: Partial<Record<string, any>>) {
  const devicesService = {
    register: jest.fn().mockResolvedValue({ id: 'server-device-row-id' }),
  };

  const tasksRepository = {
    findByIdForUser: jest.fn(),
    softDelete: jest.fn(),
    upsertWithLww: jest.fn(),
  };

  const changesRepository = {
    pull: jest.fn(),
    append: jest.fn(),
  };

  const clientMutationsRepository = {
    find: jest.fn().mockResolvedValue(null),
    create: jest.fn(),
  };

  const syncCursorsRepository = {
    upsert: jest.fn().mockResolvedValue({
      cursor: 12n,
      updatedAt: new Date('2026-03-10T12:00:00.000Z'),
    }),
  };

  Object.assign(devicesService, overrides?.devicesService);
  Object.assign(tasksRepository, overrides?.tasksRepository);
  Object.assign(changesRepository, overrides?.changesRepository);
  Object.assign(clientMutationsRepository, overrides?.clientMutationsRepository);
  Object.assign(syncCursorsRepository, overrides?.syncCursorsRepository);

  return {
    service: new SyncService(
      devicesService as any,
      tasksRepository as any,
      changesRepository as any,
      clientMutationsRepository as any,
      syncCursorsRepository as any,
    ),
    mocks: {
      devicesService,
      tasksRepository,
      changesRepository,
      clientMutationsRepository,
      syncCursorsRepository,
    },
  };
}

describe('SyncService', () => {
  const user = { id: '00000000-0000-0000-0000-000000000001' };

  it('returns duplicate result when client mutation already exists', async () => {
    const { service, mocks } = makeService({
      clientMutationsRepository: {
        find: jest.fn().mockResolvedValue({ response: { status: 'applied' } }),
      },
    });

    const response = await service.push(user as any, {
      clientDeviceId: 'ios-dev-1',
      mutations: [
        {
          clientMutationId: 'mut-1',
          entityType: SyncEntityTypeDto.TASK,
          operation: SyncMutationOperationDto.UPSERT,
          timestamp: new Date().toISOString(),
          payload: { id: 'a4b32b56-4a56-44d9-ad11-5f32f2b94dce', title: 'x' },
        },
      ],
    });

    expect(response.results[0].duplicate).toBe(true);
    expect(mocks.clientMutationsRepository.create).not.toHaveBeenCalled();
    expect(response.clientDeviceId).toBe('ios-dev-1');
    expect(response.serverDeviceId).toBe('server-device-row-id');
  });

  it('applies task upsert and records CREATED change using explicit operation', async () => {
    const task = makeTask('a4b32b56-4a56-44d9-ad11-5f32f2b94dce');
    const { service, mocks } = makeService({
      tasksRepository: {
        upsertWithLww: jest.fn().mockResolvedValue({
          task,
          applied: true,
          operation: 'created',
        }),
      },
    });

    const response = await service.push(user as any, {
      clientDeviceId: 'ios-dev-2',
      mutations: [
        {
          clientMutationId: 'mut-2',
          entityType: SyncEntityTypeDto.TASK,
          operation: SyncMutationOperationDto.UPSERT,
          entityId: task.id,
          timestamp: new Date().toISOString(),
          payload: { id: task.id, title: 'x' },
        },
      ],
    });

    expect(mocks.changesRepository.append).toHaveBeenCalledWith(
      expect.objectContaining({
        entityType: ChangeEntityType.TASK,
        operation: ChangeOperation.CREATED,
      }),
    );
    expect(response.accepted).toBe(1);
  });

  it('rejects delete-by-status in upsert flow', async () => {
    const { service } = makeService();

    await expect(
      service.push(user as any, {
        clientDeviceId: 'ios-dev-3',
        mutations: [
          {
            clientMutationId: 'mut-3',
            entityType: SyncEntityTypeDto.TASK,
            operation: SyncMutationOperationDto.UPSERT,
            entityId: 'a4b32b56-4a56-44d9-ad11-5f32f2b94dce',
            timestamp: new Date().toISOString(),
            payload: { status: 'deleted' },
          },
        ],
      }),
    ).rejects.toThrow(BadRequestException);
  });

  it('applies explicit delete mutation and writes deleted change', async () => {
    const deletedTask = {
      ...makeTask('d74ca6e6-a86a-4298-93cf-07c42053170f'),
      status: TaskStatus.DELETED,
      deletedAt: new Date('2026-03-10T12:30:00.000Z'),
    };

    const { service, mocks } = makeService({
      tasksRepository: {
        findByIdForUser: jest.fn().mockResolvedValue(makeTask(deletedTask.id)),
        softDelete: jest.fn().mockResolvedValue(deletedTask),
      },
    });

    const response = await service.push(user as any, {
      clientDeviceId: 'ios-dev-4',
      mutations: [
        {
          clientMutationId: 'mut-4',
          entityType: SyncEntityTypeDto.TASK,
          operation: SyncMutationOperationDto.DELETE,
          entityId: deletedTask.id,
          timestamp: new Date().toISOString(),
        },
      ],
    });

    expect(mocks.tasksRepository.softDelete).toHaveBeenCalled();
    expect(mocks.changesRepository.append).toHaveBeenCalledWith(
      expect.objectContaining({
        operation: ChangeOperation.DELETED,
        entityId: deletedTask.id,
      }),
    );
    expect(response.results[0]).toEqual(
      expect.objectContaining({
        duplicate: false,
      }),
    );
  });

  it('maps pull changes with lowercase operations and next cursor', async () => {
    const { service, mocks } = makeService({
      changesRepository: {
        pull: jest.fn().mockResolvedValue([
          {
            id: 11n,
            entityType: ChangeEntityType.TASK,
            entityId: 'a4b32b56-4a56-44d9-ad11-5f32f2b94dce',
            operation: ChangeOperation.UPDATED,
            occurredAt: new Date('2026-03-10T01:00:00.000Z'),
            payload: { ok: true },
          },
        ]),
      },
    });

    const response = await service.pull(user as any, { cursor: '10', limit: 1 });
    expect(mocks.changesRepository.pull).toHaveBeenCalledWith(user.id, 10n, 1);
    expect(response.cursor).toBe('11');
    expect(response.changes[0].operation).toBe('updated');
  });

  it('rejects invalid pull cursor values', async () => {
    const { service } = makeService();
    await expect(service.pull(user as any, { cursor: 'abc' })).rejects.toThrow(BadRequestException);
  });

  it('acks cursor using client device id and returns explicit ids', async () => {
    const { service } = makeService();
    const response = await service.ack(user as any, {
      clientDeviceId: 'ios-dev-5',
      cursor: '12',
    } as SyncAckDto);

    expect(response.clientDeviceId).toBe('ios-dev-5');
    expect(response.serverDeviceId).toBe('server-device-row-id');
    expect(response.cursor).toBe('12');
  });
});
