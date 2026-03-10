import { Transform, Type } from 'class-transformer';
import {
  IsArray,
  IsDateString,
  IsEnum,
  IsNotEmpty,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  ValidateNested,
} from 'class-validator';

export enum SyncEntityTypeDto {
  TASK = 'task',
  HABIT = 'habit',
  HABIT_ENTRY = 'habit_entry',
  FOCUS_SESSION = 'focus_session',
  SETTINGS = 'settings',
  ATTACHMENT = 'attachment',
}

export enum SyncMutationOperationDto {
  UPSERT = 'upsert',
  DELETE = 'delete',
}

export class SyncMutationDto {
  @IsString()
  @MaxLength(128)
  clientMutationId!: string;

  @IsEnum(SyncEntityTypeDto)
  entityType!: SyncEntityTypeDto;

  @IsEnum(SyncMutationOperationDto)
  operation!: SyncMutationOperationDto;

  @IsOptional()
  @IsUUID()
  entityId?: string;

  @IsDateString()
  timestamp!: string;

  @IsOptional()
  @IsObject()
  payload?: Record<string, unknown>;
}

export class SyncPushDto {
  @Transform(({ value, obj }) => {
    if (typeof value === 'string' && value.trim().length > 0) {
      return value;
    }
    if (typeof obj?.deviceId === 'string') {
      return obj.deviceId;
    }
    return value;
  })
  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  clientDeviceId!: string;

  // Deprecated request alias for backward compatibility.
  @IsOptional()
  @IsString()
  @MaxLength(128)
  deviceId?: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => SyncMutationDto)
  mutations!: SyncMutationDto[];
}
