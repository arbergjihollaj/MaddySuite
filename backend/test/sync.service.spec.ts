import { SyncService } from '../src/modules/sync/service/sync.service';
import { SyncEntityTypeDto, SyncMutationOperationDto } from '../src/modules/sync/dto/sync-push.dto';

describe('SyncService', () => {
  it('returns duplicate result when client mutation already exists', async () => {
    const devicesService = {
      register: jest.fn().mockResolvedValue({ id: 'device-row-id' }),
    } as any;

    const tasksRepository = {} as any;

    const changesRepository = {
      pull: jest.fn(),
      append: jest.fn(),
    } as any;

    const clientMutationsRepository = {
      find: jest.fn().mockResolvedValue({ response: { status: 'applied' } }),
      create: jest.fn(),
    } as any;

    const syncCursorsRepository = {} as any;

    const service = new SyncService(
      devicesService,
      tasksRepository,
      changesRepository,
      clientMutationsRepository,
      syncCursorsRepository,
    );

    const response = await service.push(
      { id: '00000000-0000-0000-0000-000000000001' },
      {
        deviceId: 'ios-dev-1',
        mutations: [
          {
            clientMutationId: 'mut-1',
            entityType: SyncEntityTypeDto.TASK,
            operation: SyncMutationOperationDto.UPSERT,
            timestamp: new Date().toISOString(),
            payload: { id: 'a4b32b56-4a56-44d9-ad11-5f32f2b94dce', title: 'x' },
          },
        ],
      },
    );

    expect(response.results[0].duplicate).toBe(true);
    expect(clientMutationsRepository.create).not.toHaveBeenCalled();
  });
});
