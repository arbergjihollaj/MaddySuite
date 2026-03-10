import { Injectable } from '@nestjs/common';
import { ChangeEntityType, ChangeOperation, Prisma } from '@prisma/client';
import { ChangesRepository } from '../repository/changes.repository';

@Injectable()
export class ChangesService {
  constructor(private readonly changesRepository: ChangesRepository) {}

  recordChange(input: {
    userId: string;
    entityType: ChangeEntityType;
    entityId: string;
    operation: 'CREATED' | 'UPDATED' | 'DELETED';
    payload: Record<string, unknown>;
    sourceDeviceId?: string;
    sourceMutationId?: string;
  }) {
    return this.changesRepository.append({
      userId: input.userId,
      entityType: input.entityType,
      entityId: input.entityId,
      operation: input.operation as ChangeOperation,
      payload: input.payload as Prisma.JsonObject,
      sourceDeviceId: input.sourceDeviceId,
      sourceMutationId: input.sourceMutationId,
    });
  }

  recordTaskChange(input: {
    userId: string;
    entityId: string;
    operation: 'CREATED' | 'UPDATED' | 'DELETED';
    payload: Record<string, unknown>;
    sourceDeviceId?: string;
    sourceMutationId?: string;
  }) {
    return this.recordChange({
      ...input,
      entityType: ChangeEntityType.TASK,
    });
  }
}
