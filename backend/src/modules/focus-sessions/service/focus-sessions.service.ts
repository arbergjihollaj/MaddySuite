import { Injectable } from '@nestjs/common';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { FocusSessionsRepository } from '../repository/focus-sessions.repository';

@Injectable()
export class FocusSessionsService {
  constructor(private readonly focusSessionsRepository: FocusSessionsRepository) {}

  list(user: AuthenticatedUser) {
    return this.focusSessionsRepository.listByUser(user.id);
  }
}
