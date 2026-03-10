import { Controller, Get, Param, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@/modules/auth/service/auth.guard';
import { UsersService } from '../service/users.service';

@Controller('users')
@UseGuards(AuthGuard)
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get(':id')
  getById(@Param('id') id: string) {
    return this.usersService.findById(id);
  }
}
