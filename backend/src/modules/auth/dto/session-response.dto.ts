export class SessionResponseDto {
  userId!: string;
  deviceId?: string;
  authMode!: 'dev' | 'clerk';
}
