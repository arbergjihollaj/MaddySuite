export class SessionEntity {
  userId!: string;
  deviceId?: string;
  mode!: 'dev' | 'clerk';
}
