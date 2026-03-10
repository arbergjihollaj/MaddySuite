import { Injectable } from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';

@Injectable()
export class UsersRepository {
  constructor(private readonly prisma: PrismaService) {}

  findById(id: string) {
    return this.prisma.user.findUnique({ where: { id } });
  }

  findByClerkUserId(clerkUserId: string) {
    return this.prisma.user.findUnique({ where: { clerkUserId } });
  }

  upsertById(params: { id: string; clerkUserId?: string; email?: string }) {
    return this.prisma.user.upsert({
      where: { id: params.id },
      create: {
        id: params.id,
        clerkUserId: params.clerkUserId,
        email: params.email,
      },
      update: {
        clerkUserId: params.clerkUserId,
        email: params.email,
      },
    });
  }

  upsertByClerkUserId(params: { clerkUserId: string; email?: string }) {
    return this.prisma.user.upsert({
      where: { clerkUserId: params.clerkUserId },
      create: {
        clerkUserId: params.clerkUserId,
        email: params.email,
      },
      update: {
        email: params.email,
      },
    });
  }
}
