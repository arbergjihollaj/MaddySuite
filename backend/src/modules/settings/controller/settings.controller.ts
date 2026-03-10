import { Body, Controller, Get, Put, UseGuards } from '@nestjs/common';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { CurrentUser } from '@/modules/auth/service/current-user.decorator';
import { AuthGuard } from '@/modules/auth/service/auth.guard';
import { UpsertSettingsDto } from '../dto/upsert-settings.dto';
import { SettingsService } from '../service/settings.service';

@Controller('settings')
@UseGuards(AuthGuard)
export class SettingsController {
  constructor(private readonly settingsService: SettingsService) {}

  @Get()
  get(@CurrentUser() user: AuthenticatedUser) {
    return this.settingsService.get(user);
  }

  @Put()
  upsert(@CurrentUser() user: AuthenticatedUser, @Body() dto: UpsertSettingsDto) {
    return this.settingsService.upsert(user, dto);
  }
}
