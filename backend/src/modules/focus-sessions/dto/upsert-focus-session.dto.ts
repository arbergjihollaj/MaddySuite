import { IsDateString, IsEnum, IsInt, IsUUID, Min } from 'class-validator';

export enum FocusModeDto {
  POMODORO = 'POMODORO',
  CUSTOM = 'CUSTOM',
}

export class UpsertFocusSessionDto {
  @IsUUID()
  id!: string;

  @IsDateString()
  startAt!: string;

  @IsDateString()
  endAt!: string;

  @IsInt()
  @Min(1)
  durationMinutes!: number;

  @IsEnum(FocusModeDto)
  mode!: FocusModeDto;

  @IsDateString()
  clientUpdatedAt!: string;
}
