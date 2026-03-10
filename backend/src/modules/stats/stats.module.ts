import { Module } from '@nestjs/common';
import { StatsController } from './controller/stats.controller';
import { StatsRepository } from './repository/stats.repository';
import { StatsService } from './service/stats.service';

@Module({
  controllers: [StatsController],
  providers: [StatsRepository, StatsService],
  exports: [StatsRepository, StatsService],
})
export class StatsModule {}
