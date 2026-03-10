import { z } from 'zod';

const booleanFromString = z
  .union([z.boolean(), z.string()])
  .transform((value) => {
    if (typeof value === 'boolean') return value;
    return ['1', 'true', 'yes', 'on'].includes(value.toLowerCase());
  });

const envSchema = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    PORT: z.coerce.number().int().positive().default(4000),
    API_PREFIX: z.string().default('v1'),
    APP_NAME: z.string().default('Maddy Backend'),
    APP_VERSION: z.string().default('0.1.0'),
    GIT_SHA: z.string().default('local'),

    DATABASE_URL: z.string().min(1),

    AUTH_MODE: z.enum(['dev', 'clerk']).default('dev'),
    CLERK_SECRET_KEY: z.string().optional(),
    CLERK_PUBLISHABLE_KEY: z.string().optional(),
    CLERK_ISSUER: z.string().optional(),

    S3_ENDPOINT: z.string().url(),
    S3_REGION: z.string().default('us-east-1'),
    S3_BUCKET: z.string().min(1),
    S3_ACCESS_KEY_ID: z.string().min(1),
    S3_SECRET_ACCESS_KEY: z.string().min(1),
    S3_FORCE_PATH_STYLE: booleanFromString.default(true),
    S3_UPLOAD_URL_TTL_SECONDS: z.coerce.number().int().positive().default(900),

    PG_BOSS_SCHEMA: z.string().default('pgboss'),
    PG_BOSS_ENABLED: booleanFromString.default(true),

    OTEL_SERVICE_NAME: z.string().default('maddy-backend'),
    OTEL_ENABLED: booleanFromString.default(true),
  })
  .superRefine((env, ctx) => {
    if (env.NODE_ENV === 'production' && env.AUTH_MODE === 'dev') {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['AUTH_MODE'],
        message:
          'AUTH_MODE=dev is blocked in production. Use AUTH_MODE=clerk and valid bearer-token auth.',
      });
    }

    if (env.AUTH_MODE === 'clerk' && (!env.CLERK_SECRET_KEY || env.CLERK_SECRET_KEY.trim().length === 0)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['CLERK_SECRET_KEY'],
        message: 'CLERK_SECRET_KEY is required when AUTH_MODE=clerk.',
      });
    }
  });

export type Env = z.infer<typeof envSchema>;

let cachedEnv: Env | null = null;

export function getEnv(): Env {
  if (cachedEnv) return cachedEnv;

  const parsed = envSchema.safeParse(process.env);
  if (parsed.success === false) {
    const issues = parsed.error.issues.map((issue) => `${issue.path.join('.')}: ${issue.message}`).join('\n');
    throw new Error(`Invalid environment configuration:\n${issues}`);
  }

  cachedEnv = parsed.data;
  return cachedEnv;
}

export function resetEnvCacheForTests() {
  cachedEnv = null;
}
