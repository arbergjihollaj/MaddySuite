import { Controller, Get, UseGuards } from '@nestjs/common';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { CurrentUser } from '@/modules/auth/service/current-user.decorator';
import { AuthGuard } from '@/modules/auth/service/auth.guard';
import { HabitEntriesService } from '../service/habit-entries.service';

@Controller('habit-entries')
@UseGuards(AuthGuard)
export class HabitEntriesController {
  constructor(private readonly habitEntriesService: HabitEntriesService) {}

  @Get()
  list(@CurrentUser() user: AuthenticatedUser) {
    return this.habitEntriesService.list(user);
  }
}
