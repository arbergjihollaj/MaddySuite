import { MiddlewareConsumer, Module, NestModule } from '@nestjs/common';
import { APP_FILTER, APP_INTERCEPTOR } from '@nestjs/core';
import { AppConfigModule } from '@/common/config/config.module';
import { ApiErrorFilter } from '@/common/errors/api-error.filter';
import { RequestIdMiddleware } from '@/common/http/request-id.middleware';
import { AppLoggerService } from '@/common/logger/app-logger.service';
import { PrismaModule } from '@/common/prisma/prisma.module';
import { AttachmentsModule } from '@/modules/attachments/attachments.module';
import { AuthModule } from '@/modules/auth/auth.module';
import { DevicesModule } from '@/modules/devices/devices.module';
import { FocusSessionsModule } from '@/modules/focus-sessions/focus-sessions.module';
import { HabitEntriesModule } from '@/modules/habit-entries/habit-entries.module';
import { HabitsModule } from '@/modules/habits/habits.module';
import { HealthModule } from '@/modules/health/health.module';
import { JobsModule } from '@/modules/jobs/jobs.module';
import { ObservabilityModule } from '@/modules/observability/observability.module';
import { OtelInterceptor } from '@/modules/observability/service/otel.interceptor';
import { SettingsModule } from '@/modules/settings/settings.module';
import { StatsModule } from '@/modules/stats/stats.module';
import { SyncModule } from '@/modules/sync/sync.module';
import { TasksModule } from '@/modules/tasks/tasks.module';
import { UsersModule } from '@/modules/users/users.module';

@Module({
  imports: [
    AppConfigModule,
    PrismaModule,
    ObservabilityModule,
    HealthModule,
    AuthModule,
    UsersModule,
    DevicesModule,
    TasksModule,
    HabitsModule,
    HabitEntriesModule,
    FocusSessionsModule,
    SettingsModule,
    StatsModule,
    AttachmentsModule,
    SyncModule,
    JobsModule,
  ],
  providers: [
    AppLoggerService,
    {
      provide: APP_FILTER,
      useClass: ApiErrorFilter,
    },
    {
      provide: APP_INTERCEPTOR,
      useClass: OtelInterceptor,
    },
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(RequestIdMiddleware).forRoutes('*');
  }
}
