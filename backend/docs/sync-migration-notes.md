# Sync Migration Notes (2026-03)

## API contract clarifications

- `clientDeviceId` is now the canonical client identifier in `/sync/push` and `/sync/ack`.
- `deviceId` is still accepted as a deprecated request alias for compatibility.
- Responses now include:
  - `clientDeviceId`
  - `serverDeviceId`
  - `deviceId` (deprecated alias of `clientDeviceId`)

## Delete semantics

- Task delete is only valid via `operation=delete`.
- Sending `status=deleted` inside an `operation=upsert` payload now returns `400`.

## Auth safety

- `AUTH_MODE=dev` is blocked when `NODE_ENV=production`.
- `AUTH_MODE=clerk` now requires `CLERK_SECRET_KEY`.

## Ack payload

- `SyncAckDto.userId` was removed from the contract.
- User identity is always taken from auth context.
