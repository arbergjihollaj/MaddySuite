import { Injectable } from '@nestjs/common';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { StatsRepository } from '../repository/stats.repository';

@Injectable()
export class StatsService {
  constructor(private readonly statsRepository: StatsRepository) {}

  summary(user: AuthenticatedUser) {
    return this.statsRepository.summary(user.id);
  }
}
