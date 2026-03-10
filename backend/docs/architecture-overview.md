# Architecture Overview

## Current client reality (source analysis)

Maddy iPhone + macOS apps are offline-first and currently sync by writing domain snapshots to iCloud folder JSON envelopes:

```json
{
  "modifiedAt": "...",
  "payloadData": "..."
}
```

Domains are synced independently (tasks/habits/focus/gamification/settings/calendar sources), with domain-level last-write-wins via `modifiedAt`.

## Backend target architecture

- **Style**: modular monolith
- **API runtime**: NestJS + Fastify
- **Data**: PostgreSQL + Prisma
- **Auth**: Clerk-first with dev fallback mode
- **Jobs**: pg-boss
- **Assets**: S3-compatible presigned uploads
- **Observability**: structured logs + request IDs + OTel interceptor hooks

## Module design

Each domain module follows a consistent structure:

- controller
- service
- repository
- dto
- entity

## Key boundaries

- Controllers: transport and DTO boundary validation
- Services: domain orchestration and business rules
- Repositories: persistence access only
- Sync service: idempotency, change log writes, cursor pull/ack

## Process model

- API process: serves REST and can enqueue jobs
- Worker process: starts same codebase and runs pg-boss workers

