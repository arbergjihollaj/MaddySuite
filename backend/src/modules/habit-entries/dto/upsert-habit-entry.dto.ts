import { IsDateString, IsInt, IsString, IsUUID, Min } from 'class-validator';

export class UpsertHabitEntryDto {
  @IsUUID()
  habitId!: string;

  @IsString()
  dayKey!: string;

  @IsInt()
  @Min(0)
  value!: number;

  @IsDateString()
  clientUpdatedAt!: string;
}
