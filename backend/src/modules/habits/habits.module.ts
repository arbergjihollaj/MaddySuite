import { Module } from '@nestjs/common';
import { HabitsController } from './controller/habits.controller';
import { HabitsRepository } from './repository/habits.repository';
import { HabitsService } from './service/habits.service';

@Module({
  controllers: [HabitsController],
  providers: [HabitsRepository, HabitsService],
  exports: [HabitsRepository, HabitsService],
})
export class HabitsModule {}
