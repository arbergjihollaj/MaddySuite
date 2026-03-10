import { Controller, Get, UseGuards } from '@nestjs/common';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { CurrentUser } from '@/modules/auth/service/current-user.decorator';
import { AuthGuard } from '@/modules/auth/service/auth.guard';
import { StatsService } from '../service/stats.service';

@Controller('stats')
@UseGuards(AuthGuard)
export class StatsController {
  constructor(private readonly statsService: StatsService) {}

  @Get('summary')
  summary(@CurrentUser() user: AuthenticatedUser) {
    return this.statsService.summary(user);
  }
}
