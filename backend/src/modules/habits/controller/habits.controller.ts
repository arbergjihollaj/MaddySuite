import { Controller, Get, UseGuards } from '@nestjs/common';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { CurrentUser } from '@/modules/auth/service/current-user.decorator';
import { AuthGuard } from '@/modules/auth/service/auth.guard';
import { HabitsService } from '../service/habits.service';

@Controller('habits')
@UseGuards(AuthGuard)
export class HabitsController {
  constructor(private readonly habitsService: HabitsService) {}

  @Get()
  list(@CurrentUser() user: AuthenticatedUser) {
    return this.habitsService.list(user);
  }
}
