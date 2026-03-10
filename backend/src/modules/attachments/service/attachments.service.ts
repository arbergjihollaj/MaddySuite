import { randomUUID } from 'crypto';
import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import type { Env } from '@/common/config/env';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { RequestUploadUrlDto } from '../dto/request-upload-url.dto';
import { CompleteUploadDto } from '../dto/complete-upload.dto';
import { AttachmentsRepository } from '../repository/attachments.repository';

@Injectable()
export class AttachmentsService {
  private readonly s3Client: S3Client;

  constructor(
    @Inject('ENV') private readonly env: Env,
    private readonly attachmentsRepository: AttachmentsRepository,
  ) {
    this.s3Client = new S3Client({
      region: env.S3_REGION,
      endpoint: env.S3_ENDPOINT,
      forcePathStyle: env.S3_FORCE_PATH_STYLE,
      credentials: {
        accessKeyId: env.S3_ACCESS_KEY_ID,
        secretAccessKey: env.S3_SECRET_ACCESS_KEY,
      },
    });
  }

  async requestUploadUrl(user: AuthenticatedUser, dto: RequestUploadUrlDto) {
    const attachmentId = randomUUID();
    const extension = this.extension(dto.fileName);
    const objectKey = `${user.id}/${new Date().toISOString().slice(0, 10)}/${attachmentId}${extension}`;

    const putCommand = new PutObjectCommand({
      Bucket: this.env.S3_BUCKET,
      Key: objectKey,
      ContentType: dto.contentType,
      Metadata: {
        userId: user.id,
        attachmentId,
      },
    });

    const uploadUrl = await getSignedUrl(this.s3Client, putCommand, {
      expiresIn: this.env.S3_UPLOAD_URL_TTL_SECONDS,
    });

    const created = await this.attachmentsRepository.createPending({
      userId: user.id,
      taskId: dto.taskId,
      habitId: dto.habitId,
      objectKey,
      bucket: this.env.S3_BUCKET,
      fileName: dto.fileName,
      contentType: dto.contentType,
      sizeBytes: dto.sizeBytes,
      metadata: {},
    });

    return {
      attachmentId: created.id,
      objectKey,
      uploadUrl,
      method: 'PUT',
      headers: {
        'Content-Type': dto.contentType,
      },
      expiresInSeconds: this.env.S3_UPLOAD_URL_TTL_SECONDS,
    };
  }

  async completeUpload(user: AuthenticatedUser, id: string, dto: CompleteUploadDto) {
    const attachment = await this.attachmentsRepository.findByIdForUser(id, user.id);
    if (!attachment) {
      throw new NotFoundException('Attachment not found');
    }

    return this.attachmentsRepository.markReady({
      id,
      etag: dto.etag,
      sizeBytes: dto.sizeBytes,
    });
  }

  async downloadUrl(user: AuthenticatedUser, id: string) {
    const attachment = await this.attachmentsRepository.findByIdForUser(id, user.id);
    if (!attachment) {
      throw new NotFoundException('Attachment not found');
    }

    const command = new GetObjectCommand({
      Bucket: attachment.bucket,
      Key: attachment.objectKey,
    });

    const url = await getSignedUrl(this.s3Client, command, {
      expiresIn: this.env.S3_UPLOAD_URL_TTL_SECONDS,
    });

    return {
      attachmentId: attachment.id,
      url,
      expiresInSeconds: this.env.S3_UPLOAD_URL_TTL_SECONDS,
    };
  }

  list(user: AuthenticatedUser) {
    return this.attachmentsRepository.listByUser(user.id);
  }

  private extension(fileName: string): string {
    const index = fileName.lastIndexOf('.');
    if (index <= 0) return '';
    return fileName.slice(index);
  }
}
