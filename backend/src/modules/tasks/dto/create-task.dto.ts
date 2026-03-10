import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsDateString,
  IsEnum,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';
import { TaskDifficultyDto, TaskPriorityDto, TaskStatusDto } from './task-enums.dto';

export class CreateTaskDto {
  @IsOptional()
  @IsUUID()
  id?: string;

  @IsString()
  @MaxLength(255)
  title!: string;

  @IsOptional()
  @IsDateString()
  dueAt?: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(32)
  @IsString({ each: true })
  @MaxLength(64, { each: true })
  tags?: string[];

  @IsOptional()
  @IsEnum(TaskStatusDto)
  status?: TaskStatusDto;

  @IsOptional()
  @IsEnum(TaskDifficultyDto)
  difficulty?: TaskDifficultyDto;

  @IsOptional()
  @IsEnum(TaskPriorityDto)
  priority?: TaskPriorityDto;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(2)
  @IsString({ each: true })
  mappedSkills?: string[];

  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  isDailyTask?: boolean;

  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  isRequiredDailyTask?: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(32)
  dailyDateKey?: string;

  @IsOptional()
  @IsDateString()
  completedAt?: string;

  @IsOptional()
  @IsDateString()
  clientUpdatedAt?: string;
}
