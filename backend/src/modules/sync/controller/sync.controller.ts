import { Body, Controller, Get, Post, Query, UseGuards } from '@nestjs/common';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { CurrentUser } from '@/modules/auth/service/current-user.decorator';
import { AuthGuard } from '@/modules/auth/service/auth.guard';
import { SyncAckDto } from '../dto/sync-ack.dto';
import { SyncPullQueryDto } from '../dto/sync-pull.dto';
import { SyncPushDto } from '../dto/sync-push.dto';
import { SyncService } from '../service/sync.service';

@Controller('sync')
@UseGuards(AuthGuard)
export class SyncController {
  constructor(private readonly syncService: SyncService) {}

  @Post('push')
  push(@CurrentUser() user: AuthenticatedUser, @Body() dto: SyncPushDto) {
    return this.syncService.push(user, dto);
  }

  @Get('pull')
  pull(@CurrentUser() user: AuthenticatedUser, @Query() query: SyncPullQueryDto) {
    return this.syncService.pull(user, query);
  }

  @Post('ack')
  ack(@CurrentUser() user: AuthenticatedUser, @Body() dto: SyncAckDto) {
    return this.syncService.ack(user, dto);
  }
}
