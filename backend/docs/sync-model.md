# Sync Model

## Endpoints

- `POST /sync/push`
- `GET /sync/pull?cursor=`
- `POST /sync/ack`

## Push contract

Each mutation includes:

- `clientMutationId`
- `deviceId` (request-level)
- `timestamp`
- `entityType`
- `operation`
- `payload`

## Idempotency

Dedup key:

- `(user_id, device_id, client_mutation_id)`

Stored in `client_mutations`.

If duplicate arrives, stored response is returned.

## Change log

Every applied mutation writes to append-only `changes` table.

Ordering:

- deterministic by `changes.id ASC`

## Pull contract

`GET /sync/pull?cursor=<lastSeenCursor>`

Response:

- `cursor`: new cursor
- `hasMore`
- `changes[]`

## Conflict strategy (initial)

- Last-write-wins using `client_updated_at`
- If incoming mutation is older than stored record, mutation is ignored and returned as such

