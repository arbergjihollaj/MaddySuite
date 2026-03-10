import { IsEnum, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

export enum DevicePlatformDto {
  IOS = 'IOS',
  MACOS = 'MACOS',
  UNKNOWN = 'UNKNOWN',
}

export class RegisterDeviceDto {
  @IsUUID()
  userId!: string;

  @IsString()
  @MaxLength(128)
  clientDeviceId!: string;

  @IsOptional()
  @IsEnum(DevicePlatformDto)
  platform?: DevicePlatformDto;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  appVersion?: string;
}
