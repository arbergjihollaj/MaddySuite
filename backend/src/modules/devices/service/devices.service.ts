import { Injectable } from '@nestjs/common';
import { DevicePlatform } from '@prisma/client';
import { DevicesRepository } from '../repository/devices.repository';

@Injectable()
export class DevicesService {
  constructor(private readonly devicesRepository: DevicesRepository) {}

  register(params: {
    userId: string;
    clientDeviceId: string;
    platform?: DevicePlatform;
    appVersion?: string;
  }) {
    return this.devicesRepository.upsert(params);
  }

  findByUserAndClientId(userId: string, clientDeviceId: string) {
    return this.devicesRepository.findByUserAndClientId(userId, clientDeviceId);
  }
}
