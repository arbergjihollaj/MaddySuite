import { IsObject, IsOptional, IsString, MaxLength } from 'class-validator';

export class EnqueueJobDto {
  @IsString()
  @MaxLength(128)
  name!: string;

  @IsOptional()
  @IsObject()
  payload?: Record<string, unknown>;
}
