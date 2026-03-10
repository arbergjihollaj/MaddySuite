# Data Model

Primary tables:

- `users`
- `devices`
- `tasks`
- `habits`
- `habit_entries`
- `focus_sessions`
- `settings`
- `attachments`
- `sync_cursors`
- `changes` (append-only)
- `outbox_events`
- `client_mutations` (idempotency)

## Sync-critical columns

- Every mutable sync entity has `client_updated_at` and `updated_at`
- LWW decisions are currently made by `client_updated_at`
- `changes.id` (BIGSERIAL) is the sync cursor and deterministic ordering source

## JSONB usage

Used only where flexibility is needed:

- `tasks.tags`
- `tasks.mapped_skills`
- `settings.payload`
- `attachments.metadata`
- `changes.payload`
- `outbox_events.payload`
- `client_mutations.response`

