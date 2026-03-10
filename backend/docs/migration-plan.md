# Migration Plan: Folder Sync -> Backend Sync

## Current state

Clients currently sync by writing full-domain JSON snapshots to shared iCloud folder files.

## Target state

Clients continue local-first writes, but sync via backend mutation/pull cursor API.

## Recommended transition strategy

### Phase A - Dual-read readiness (server introduced)

- Ship backend + auth + sync endpoints
- Keep existing folder sync enabled as primary path
- Add backend sync capability flag in app settings/config

### Phase B - Dual-write (controlled rollout)

- Clients still write local storage as source of truth
- Clients push mutations to backend in parallel
- Clients pull backend changes and compare with local snapshots
- Keep folder sync fallback for safety

### Phase C - Backend primary

- Make backend sync default
- Keep folder sync as emergency fallback behind hidden flag

### Phase D - Folder sync retirement

- Disable folder sync by default
- Keep one import tool for historical folder files

## Feature flags

Recommended flags:

- `sync.backend.enabled`
- `sync.folder.fallback.enabled`
- `sync.dualwrite.enabled`
- `sync.conflict.telemetry.enabled`

## Data migration scaffolding

Server should accept first sync seed from clients:

- client performs initial push with current local entities
- server stores entities and emits changes
- client switches to cursor pull loop

## Risk controls

- idempotent mutation processing
- per-device cursor checkpointing
- server-side mutation audit trail (`changes`, `client_mutations`)
- canary rollout by user cohort

