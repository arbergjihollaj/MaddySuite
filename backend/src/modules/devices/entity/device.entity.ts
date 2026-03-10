export class DeviceEntity {
  id!: string;
  userId!: string;
  clientDeviceId!: string;
  platform!: 'IOS' | 'MACOS' | 'UNKNOWN';
  appVersion?: string | null;
  lastSeenAt?: Date | null;
  createdAt!: Date;
  updatedAt!: Date;
}
