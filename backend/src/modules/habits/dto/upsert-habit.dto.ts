import { IsArray, IsDateString, IsInt, IsOptional, IsString, IsUUID, MaxLength, Min } from 'class-validator';

export class UpsertHabitDto {
  @IsUUID()
  id!: string;

  @IsString()
  @MaxLength(255)
  title!: string;

  @IsString()
  symbol!: string;

  @IsString()
  colorHex!: string;

  @IsString()
  goalKind!: string;

  @IsInt()
  @Min(1)
  targetValue!: number;

  @IsString()
  scheduleMode!: string;

  @IsArray()
  weekdays!: number[];

  @IsInt()
  @Min(1)
  everyXDays!: number;

  @IsOptional()
  @IsInt()
  streak?: number;

  @IsOptional()
  @IsString()
  lastCompletedDateKey?: string;

  @IsDateString()
  clientUpdatedAt!: string;
}
