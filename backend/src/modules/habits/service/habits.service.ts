import { Injectable } from '@nestjs/common';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { HabitsRepository } from '../repository/habits.repository';

@Injectable()
export class HabitsService {
  constructor(private readonly habitsRepository: HabitsRepository) {}

  list(user: AuthenticatedUser) {
    return this.habitsRepository.listByUser(user.id);
  }
}
