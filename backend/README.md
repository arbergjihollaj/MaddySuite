# Maddy Backend (NestJS + Fastify + Prisma)

Production-ready backend foundation for Maddy's offline-first Apple app suite (iPhone + macOS).

## What this backend provides

- Modular monolith architecture (single codebase for API + optional worker)
- NestJS + Fastify REST API
- PostgreSQL + Prisma schema/migrations
- Clerk-ready authentication abstraction (with `AUTH_MODE=dev` fallback)
- Device registration and session context
- Sync foundation with:
  - idempotent mutation handling
  - append-only change log
  - cursor-based pull
  - deterministic ordering
- Task domain CRUD + sync integration
- Attachment presigned upload flow (S3-compatible)
- pg-boss job worker foundation
- OpenAPI docs endpoint
- Structured logs + request IDs + OpenTelemetry interceptor hooks
- Health/readiness/version endpoints

## Repository placement

This backend lives in:

- `backend/`

## Prerequisites

- Node.js 20+
- npm 10+
- PostgreSQL 15+

## Local setup

1. Copy env file:

```bash
cp .env.example .env
```

2. Install dependencies:

```bash
npm install
```

3. Generate Prisma client and migrate:

```bash
npm run prisma:generate
npm run prisma:migrate
```

4. Start API:

```bash
npm run start:dev
```

5. Optional worker process:

```bash
npm run start:worker
```

## API endpoints (core)

- `GET /v1/health/live`
- `GET /v1/health/ready`
- `GET /v1/version`
- `GET /v1/auth/session`
- `POST /v1/devices/register`
- `GET /v1/tasks`
- `POST /v1/tasks`
- `PATCH /v1/tasks/:id`
- `DELETE /v1/tasks/:id`
- `POST /v1/sync/push`
- `GET /v1/sync/pull?cursor=`
- `POST /v1/sync/ack`
- `POST /v1/attachments/presign-upload`
- `POST /v1/attachments/:id/complete`
- `GET /v1/attachments/:id/download-url`

OpenAPI UI:

- `GET /v1/docs`

## Environment variables

See `.env.example` for full list.

Key variables:

- `DATABASE_URL`
- `AUTH_MODE` (`dev` or `clerk`)
- `CLERK_SECRET_KEY`
- `S3_*`
- `PG_BOSS_ENABLED`
- `OTEL_ENABLED`

## Documentation

- `docs/architecture-overview.md`
- `docs/module-boundaries.md`
- `docs/data-model.md`
- `docs/sync-model.md`
- `docs/sync-migration-notes.md`
- `docs/migration-plan.md`
- `openapi/openapi.yaml`
