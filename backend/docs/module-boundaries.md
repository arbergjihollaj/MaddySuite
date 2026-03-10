# Module Boundaries

## auth

- validates auth/session context
- maps bearer/dev headers to internal user/device context

## users

- user lifecycle persistence (`users` table)

## devices

- device registration + last seen updates
- stable `client_device_id` per user

## tasks

- task CRUD
- LWW merge helper for sync apply

## habits / habit_entries / focus_sessions

- foundational endpoints/repositories for upcoming full sync parity

## settings

- JSON settings payload upsert/read

## attachments

- presign upload URLs
- metadata persistence
- signed download URLs

## sync

- `/sync/push`, `/sync/pull`, `/sync/ack`
- mutation idempotency (`client_mutations`)
- append-only changes log (`changes`)
- cursor tracking (`sync_cursors`)

## jobs

- pg-boss lifecycle
- queue handlers and outbox draining scaffold

## health

- liveness/readiness/version

## observability

- OTel HTTP interceptor
- capabilities endpoint for diagnostics

