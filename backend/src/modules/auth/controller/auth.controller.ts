import { Controller, Get, UseGuards } from '@nestjs/common';
import { CurrentUser } from '@/modules/auth/service/current-user.decorator';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { AuthGuard } from '../service/auth.guard';

@Controller('auth')
export class AuthController {
  @Get('session')
  @UseGuards(AuthGuard)
  session(@CurrentUser() user: AuthenticatedUser) {
    return {
      userId: user.id,
      deviceId: user.deviceId,
      authMode: process.env.AUTH_MODE ?? 'dev',
    };
  }
}
