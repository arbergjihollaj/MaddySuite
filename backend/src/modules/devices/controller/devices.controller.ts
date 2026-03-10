import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { DevicePlatform } from '@prisma/client';
import { CurrentUser } from '@/modules/auth/service/current-user.decorator';
import { AuthGuard } from '@/modules/auth/service/auth.guard';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { RegisterDeviceDto } from '../dto/register-device.dto';
import { DevicesService } from '../service/devices.service';

@Controller('devices')
@UseGuards(AuthGuard)
export class DevicesController {
  constructor(private readonly devicesService: DevicesService) {}

  @Post('register')
  async register(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: RegisterDeviceDto,
  ) {
    return this.devicesService.register({
      userId: user.id,
      clientDeviceId: dto.clientDeviceId,
      platform: (dto.platform as DevicePlatform | undefined) ?? DevicePlatform.UNKNOWN,
      appVersion: dto.appVersion,
    });
  }
}
