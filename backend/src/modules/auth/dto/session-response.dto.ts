export class SessionResponseDto {
  userId!: string;
  clientDeviceId?: string;
  serverDeviceId?: string;
  // Deprecated alias for compatibility.
  deviceId?: string;
  authMode!: 'dev' | 'clerk';
}
