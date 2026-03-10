import { Injectable } from '@nestjs/common';
import { UsersRepository } from '../repository/users.repository';

@Injectable()
export class UsersService {
  constructor(private readonly usersRepository: UsersRepository) {}

  findById(id: string) {
    return this.usersRepository.findById(id);
  }

  ensureDevUser(userId: string, email?: string) {
    return this.usersRepository.upsertById({ id: userId, email });
  }

  ensureClerkUser(clerkUserId: string, email?: string) {
    return this.usersRepository.upsertByClerkUserId({ clerkUserId, email });
  }
}
