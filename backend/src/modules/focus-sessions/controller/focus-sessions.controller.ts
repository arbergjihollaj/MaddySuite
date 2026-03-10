import { Controller, Get, UseGuards } from '@nestjs/common';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { CurrentUser } from '@/modules/auth/service/current-user.decorator';
import { AuthGuard } from '@/modules/auth/service/auth.guard';
import { FocusSessionsService } from '../service/focus-sessions.service';

@Controller('focus-sessions')
@UseGuards(AuthGuard)
export class FocusSessionsController {
  constructor(private readonly focusSessionsService: FocusSessionsService) {}

  @Get()
  list(@CurrentUser() user: AuthenticatedUser) {
    return this.focusSessionsService.list(user);
  }
}
