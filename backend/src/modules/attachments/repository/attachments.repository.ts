import { Injectable } from '@nestjs/common';
import { AttachmentStatus } from '@prisma/client';
import { PrismaService } from '@/common/prisma/prisma.service';

@Injectable()
export class AttachmentsRepository {
  constructor(private readonly prisma: PrismaService) {}

  createPending(params: {
    userId: string;
    taskId?: string;
    habitId?: string;
    objectKey: string;
    bucket: string;
    fileName: string;
    contentType: string;
    sizeBytes?: number;
    metadata?: Record<string, unknown>;
  }) {
    return this.prisma.attachment.create({
      data: {
        userId: params.userId,
        taskId: params.taskId,
        habitId: params.habitId,
        objectKey: params.objectKey,
        bucket: params.bucket,
        fileName: params.fileName,
        contentType: params.contentType,
        sizeBytes: params.sizeBytes,
        metadata: params.metadata ?? {},
        status: AttachmentStatus.PENDING,
        clientUpdatedAt: new Date(),
      },
    });
  }

  findByIdForUser(id: string, userId: string) {
    return this.prisma.attachment.findFirst({ where: { id, userId } });
  }

  markReady(params: { id: string; etag?: string; sizeBytes?: number }) {
    return this.prisma.attachment.update({
      where: { id: params.id },
      data: {
        status: AttachmentStatus.READY,
        etag: params.etag,
        sizeBytes: params.sizeBytes,
        clientUpdatedAt: new Date(),
      },
    });
  }

  listByUser(userId: string) {
    return this.prisma.attachment.findMany({
      where: { userId, status: { not: AttachmentStatus.DELETED } },
      orderBy: [{ updatedAt: 'desc' }],
    });
  }
}
