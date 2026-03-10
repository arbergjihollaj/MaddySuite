import { IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';

export class RequestUploadUrlDto {
  @IsString()
  @MaxLength(255)
  fileName!: string;

  @IsString()
  @MaxLength(255)
  contentType!: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(1024 * 1024 * 100)
  sizeBytes?: number;

  @IsOptional()
  @IsUUID()
  taskId?: string;

  @IsOptional()
  @IsUUID()
  habitId?: string;
}
