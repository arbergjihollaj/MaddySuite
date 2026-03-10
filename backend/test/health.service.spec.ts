import { HealthService } from '../src/modules/health/service/health.service';

describe('HealthService', () => {
  it('returns liveness payload', async () => {
    const prismaMock = {
      $queryRaw: jest.fn().mockResolvedValue([{ '?column?': 1 }]),
    } as any;

    const env = {
      APP_NAME: 'Maddy Backend',
      APP_VERSION: '0.1.0',
      GIT_SHA: 'test',
      NODE_ENV: 'test',
    } as any;

    const service = new HealthService(prismaMock, env);
    const live = service.liveness();

    expect(live.status).toBe('ok');
    expect(live.service).toBe('Maddy Backend');

    const ready = await service.readiness();
    expect(ready.status).toBe('ready');
    expect(prismaMock.$queryRaw).toHaveBeenCalled();
  });
});
