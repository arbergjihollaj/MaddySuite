import { Injectable } from '@nestjs/common';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { HabitEntriesRepository } from '../repository/habit-entries.repository';

@Injectable()
export class HabitEntriesService {
  constructor(private readonly habitEntriesRepository: HabitEntriesRepository) {}

  list(user: AuthenticatedUser) {
    return this.habitEntriesRepository.listByUser(user.id);
  }
}
