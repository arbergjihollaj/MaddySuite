import { Module } from '@nestjs/common';
import { HabitEntriesController } from './controller/habit-entries.controller';
import { HabitEntriesRepository } from './repository/habit-entries.repository';
import { HabitEntriesService } from './service/habit-entries.service';

@Module({
  controllers: [HabitEntriesController],
  providers: [HabitEntriesRepository, HabitEntriesService],
  exports: [HabitEntriesRepository, HabitEntriesService],
})
export class HabitEntriesModule {}
