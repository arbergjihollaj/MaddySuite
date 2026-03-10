import { IsDateString, IsObject } from 'class-validator';

export class UpsertSettingsDto {
  @IsObject()
  payload!: Record<string, unknown>;

  @IsDateString()
  clientUpdatedAt!: string;
}
