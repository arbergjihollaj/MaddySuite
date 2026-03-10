import { Transform } from 'class-transformer';
import { IsNotEmpty, IsOptional, IsString, Matches, MaxLength } from 'class-validator';

export class SyncAckDto {
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

  @IsString()
  @Matches(/^\d+$/)
  cursor!: string;
}
