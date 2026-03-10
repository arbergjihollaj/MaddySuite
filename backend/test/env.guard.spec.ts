import { getEnv, resetEnvCacheForTests } from '../src/common/config/env';

const baselineEnv = {
  PORT: '4000',
  API_PREFIX: 'v1',
  APP_NAME: 'Maddy Backend',
  APP_VERSION: '0.1.0',
  GIT_SHA: 'test',
  DATABASE_URL: 'postgresql://localhost:5432/maddy',
  S3_ENDPOINT: 'https://s3.example.com',
  S3_BUCKET: 'bucket',
  S3_ACCESS_KEY_ID: 'key',
  S3_SECRET_ACCESS_KEY: 'secret',
};

describe('Environment security guards', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    jest.resetModules();
    resetEnvCacheForTests();
    process.env = { ...baselineEnv };
  });

  afterAll(() => {
    process.env = originalEnv;
    resetEnvCacheForTests();
  });

  it('blocks AUTH_MODE=dev in production', () => {
    process.env.NODE_ENV = 'production';
    process.env.AUTH_MODE = 'dev';

    expect(() => getEnv()).toThrow(/AUTH_MODE=dev is blocked in production/i);
  });

  it('requires Clerk secret when AUTH_MODE=clerk', () => {
    process.env.NODE_ENV = 'production';
    process.env.AUTH_MODE = 'clerk';
    delete process.env.CLERK_SECRET_KEY;

    expect(() => getEnv()).toThrow(/CLERK_SECRET_KEY is required/i);
  });

  it('accepts production config when AUTH_MODE=clerk with secret', () => {
    process.env.NODE_ENV = 'production';
    process.env.AUTH_MODE = 'clerk';
    process.env.CLERK_SECRET_KEY = 'sk_test_123';

    const env = getEnv();
    expect(env.NODE_ENV).toBe('production');
    expect(env.AUTH_MODE).toBe('clerk');
  });
});
