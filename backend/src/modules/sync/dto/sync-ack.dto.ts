import { IsString, IsUUID, MaxLength } from 'class-validator';

export class SyncAckDto {
  @IsString()
  @MaxLength(128)
  deviceId!: string;

  @IsString()
  cursor!: string;

  @IsUUID()
  userId?: string;
}
