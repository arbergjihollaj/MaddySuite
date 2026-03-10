import { Controller, Get, Inject, UseGuards } from '@nestjs/common';
import type { Env } from '@/common/config/env';
import { CurrentUser } from '@/modules/auth/service/current-user.decorator';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { AuthGuard } from '../service/auth.guard';

@Controller('auth')
export class AuthController {
  constructor(@Inject('ENV') private readonly env: Env) {}

  @Get('session')
  @UseGuards(AuthGuard)
  session(@CurrentUser() user: AuthenticatedUser) {
    return {
      userId: user.id,
      clientDeviceId: user.clientDeviceId,
      serverDeviceId: user.serverDeviceId ?? user.deviceId,
      // Deprecated alias for compatibility.
      deviceId: user.serverDeviceId ?? user.deviceId,
      authMode: this.env.AUTH_MODE,
    };
  }
}
