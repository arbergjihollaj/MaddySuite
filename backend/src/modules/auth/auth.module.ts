import { Module } from '@nestjs/common';
import { DevicesModule } from '@/modules/devices/devices.module';
import { UsersModule } from '@/modules/users/users.module';
import { AuthController } from './controller/auth.controller';
import { AuthRepository } from './repository/auth.repository';
import { AuthGuard } from './service/auth.guard';
import { AuthService } from './service/auth.service';

@Module({
  imports: [UsersModule, DevicesModule],
  controllers: [AuthController],
  providers: [AuthRepository, AuthService, AuthGuard],
  exports: [AuthService, AuthGuard],
})
export class AuthModule {}
