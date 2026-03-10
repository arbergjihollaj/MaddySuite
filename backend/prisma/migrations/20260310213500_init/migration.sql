-- Initial backend schema for Maddy modular monolith

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TYPE "DevicePlatform" AS ENUM ('IOS', 'MACOS', 'UNKNOWN');
CREATE TYPE "TaskStatus" AS ENUM ('BACKLOG', 'IN_PROGRESS', 'DONE', 'MISSED', 'DELETED');
CREATE TYPE "TaskDifficulty" AS ENUM ('EASY', 'MEDIUM', 'HARD');
CREATE TYPE "TaskPriority" AS ENUM ('LOW', 'MEDIUM', 'HIGH');
CREATE TYPE "FocusMode" AS ENUM ('POMODORO', 'CUSTOM');
CREATE TYPE "AttachmentStatus" AS ENUM ('PENDING', 'READY', 'DELETED');
CREATE TYPE "ChangeEntityType" AS ENUM ('TASK', 'HABIT', 'HABIT_ENTRY', 'FOCUS_SESSION', 'SETTINGS', 'ATTACHMENT', 'DEVICE');
CREATE TYPE "ChangeOperation" AS ENUM ('CREATED', 'UPDATED', 'DELETED');
CREATE TYPE "OutboxStatus" AS ENUM ('PENDING', 'PROCESSING', 'DONE', 'FAILED');

CREATE TABLE "users" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "clerk_user_id" TEXT UNIQUE,
    "email" TEXT,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE "devices" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
    "client_device_id" TEXT NOT NULL,
    "platform" "DevicePlatform" NOT NULL DEFAULT 'UNKNOWN',
    "app_version" TEXT,
    "last_seen_at" TIMESTAMPTZ,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("user_id", "client_device_id")
);
CREATE INDEX "devices_user_id_idx" ON "devices"("user_id");

CREATE TABLE "tasks" (
    "id" UUID PRIMARY KEY,
    "user_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
    "title" TEXT NOT NULL,
    "due_at" TIMESTAMPTZ,
    "tags" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "status" "TaskStatus" NOT NULL DEFAULT 'BACKLOG',
    "difficulty" "TaskDifficulty" NOT NULL DEFAULT 'MEDIUM',
    "priority" "TaskPriority" NOT NULL DEFAULT 'MEDIUM',
    "mapped_skills" JSONB NOT NULL DEFAULT '["execution"]'::jsonb,
    "is_daily_task" BOOLEAN NOT NULL DEFAULT false,
    "is_required_daily_task" BOOLEAN NOT NULL DEFAULT false,
    "daily_date_key" TEXT,
    "completed_at" TIMESTAMPTZ,
    "deleted_at" TIMESTAMPTZ,
    "client_updated_at" TIMESTAMPTZ NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "tasks_user_id_updated_at_idx" ON "tasks"("user_id", "updated_at");
CREATE INDEX "tasks_user_id_deleted_at_idx" ON "tasks"("user_id", "deleted_at");

CREATE TABLE "habits" (
    "id" UUID PRIMARY KEY,
    "user_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
    "title" TEXT NOT NULL,
    "symbol" TEXT NOT NULL,
    "color_hex" TEXT NOT NULL,
    "goal_kind" TEXT NOT NULL,
    "target_value" INT NOT NULL,
    "schedule_mode" TEXT NOT NULL,
    "weekdays" JSONB NOT NULL DEFAULT '[]'::jsonb,
    "every_x_days" INT NOT NULL DEFAULT 1,
    "streak" INT NOT NULL DEFAULT 0,
    "last_completed_date_key" TEXT,
    "deleted_at" TIMESTAMPTZ,
    "client_updated_at" TIMESTAMPTZ NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "habits_user_id_updated_at_idx" ON "habits"("user_id", "updated_at");

CREATE TABLE "habit_entries" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
    "habit_id" UUID NOT NULL REFERENCES "habits"("id") ON DELETE CASCADE,
    "day_key" TEXT NOT NULL,
    "value" INT NOT NULL DEFAULT 0,
    "client_updated_at" TIMESTAMPTZ NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("habit_id", "day_key")
);
CREATE INDEX "habit_entries_user_id_updated_at_idx" ON "habit_entries"("user_id", "updated_at");

CREATE TABLE "focus_sessions" (
    "id" UUID PRIMARY KEY,
    "user_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
    "device_id" UUID,
    "start_at" TIMESTAMPTZ NOT NULL,
    "end_at" TIMESTAMPTZ NOT NULL,
    "duration_minutes" INT NOT NULL,
    "mode" "FocusMode" NOT NULL,
    "deleted_at" TIMESTAMPTZ,
    "client_updated_at" TIMESTAMPTZ NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "focus_sessions_user_id_updated_at_idx" ON "focus_sessions"("user_id", "updated_at");

CREATE TABLE "settings" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL UNIQUE REFERENCES "users"("id") ON DELETE CASCADE,
    "payload" JSONB NOT NULL DEFAULT '{}'::jsonb,
    "client_updated_at" TIMESTAMPTZ NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE "attachments" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
    "task_id" UUID,
    "habit_id" UUID,
    "object_key" TEXT NOT NULL,
    "bucket" TEXT NOT NULL,
    "file_name" TEXT NOT NULL,
    "content_type" TEXT NOT NULL,
    "size_bytes" INT,
    "etag" TEXT,
    "status" "AttachmentStatus" NOT NULL DEFAULT 'PENDING',
    "metadata" JSONB NOT NULL DEFAULT '{}'::jsonb,
    "client_updated_at" TIMESTAMPTZ NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "attachments_user_id_updated_at_idx" ON "attachments"("user_id", "updated_at");

CREATE TABLE "sync_cursors" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
    "device_id" UUID NOT NULL REFERENCES "devices"("id") ON DELETE CASCADE,
    "cursor" BIGINT NOT NULL DEFAULT 0,
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("user_id", "device_id")
);

CREATE TABLE "changes" (
    "id" BIGSERIAL PRIMARY KEY,
    "user_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
    "entity_type" "ChangeEntityType" NOT NULL,
    "entity_id" UUID NOT NULL,
    "operation" "ChangeOperation" NOT NULL,
    "payload" JSONB NOT NULL DEFAULT '{}'::jsonb,
    "occurred_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "source_device_id" UUID,
    "source_mutation_id" TEXT
);
CREATE INDEX "changes_user_id_id_idx" ON "changes"("user_id", "id");
CREATE INDEX "changes_user_id_occurred_at_idx" ON "changes"("user_id", "occurred_at");

CREATE TABLE "outbox_events" (
    "id" BIGSERIAL PRIMARY KEY,
    "user_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
    "topic" TEXT NOT NULL,
    "payload" JSONB NOT NULL,
    "status" "OutboxStatus" NOT NULL DEFAULT 'PENDING',
    "attempts" INT NOT NULL DEFAULT 0,
    "available_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "outbox_events_status_available_at_idx" ON "outbox_events"("status", "available_at");

CREATE TABLE "client_mutations" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
    "device_id" UUID NOT NULL REFERENCES "devices"("id") ON DELETE CASCADE,
    "client_mutation_id" TEXT NOT NULL,
    "mutation_type" TEXT NOT NULL,
    "entity_type" "ChangeEntityType",
    "entity_id" UUID,
    "response" JSONB,
    "processed_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE("user_id", "device_id", "client_mutation_id")
);
CREATE INDEX "client_mutations_user_id_processed_at_idx" ON "client_mutations"("user_id", "processed_at");

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER set_users_updated_at BEFORE UPDATE ON "users" FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER set_devices_updated_at BEFORE UPDATE ON "devices" FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER set_tasks_updated_at BEFORE UPDATE ON "tasks" FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER set_habits_updated_at BEFORE UPDATE ON "habits" FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER set_habit_entries_updated_at BEFORE UPDATE ON "habit_entries" FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER set_focus_sessions_updated_at BEFORE UPDATE ON "focus_sessions" FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER set_settings_updated_at BEFORE UPDATE ON "settings" FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER set_attachments_updated_at BEFORE UPDATE ON "attachments" FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER set_sync_cursors_updated_at BEFORE UPDATE ON "sync_cursors" FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER set_outbox_events_updated_at BEFORE UPDATE ON "outbox_events" FOR EACH ROW EXECUTE FUNCTION set_updated_at();
