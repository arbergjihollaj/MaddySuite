import { Injectable } from '@nestjs/common';
import { ChangeEntityType } from '@prisma/client';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { ChangesService } from '@/modules/sync/service/changes.service';
import { UpsertSettingsDto } from '../dto/upsert-settings.dto';
import { SettingsRepository } from '../repository/settings.repository';

@Injectable()
export class SettingsService {
  constructor(
    private readonly settingsRepository: SettingsRepository,
    private readonly changesService: ChangesService,
  ) {}

  async get(user: AuthenticatedUser) {
    return this.settingsRepository.getByUser(user.id);
  }

  async upsert(user: AuthenticatedUser, dto: UpsertSettingsDto) {
    const saved = await this.settingsRepository.upsert(user.id, dto.payload, new Date(dto.clientUpdatedAt));

    await this.changesService.recordChange({
      userId: user.id,
      entityType: ChangeEntityType.SETTINGS,
      entityId: saved.id,
      operation: 'UPDATED',
      payload: {
        settingsId: saved.id,
        payload: saved.payload,
        updatedAt: saved.updatedAt.toISOString(),
      },
      sourceDeviceId: user.deviceId,
    });

    return saved;
  }
}
