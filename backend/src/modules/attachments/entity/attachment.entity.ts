export class AttachmentEntity {
  id!: string;
  userId!: string;
  taskId?: string | null;
  habitId?: string | null;
  objectKey!: string;
  bucket!: string;
  fileName!: string;
  contentType!: string;
  sizeBytes?: number | null;
  etag?: string | null;
  status!: 'PENDING' | 'READY' | 'DELETED';
  metadata!: Record<string, unknown>;
  clientUpdatedAt!: string;
  createdAt!: string;
  updatedAt!: string;
}
