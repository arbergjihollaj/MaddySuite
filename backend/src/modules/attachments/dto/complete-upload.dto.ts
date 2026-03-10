import { IsInt, IsOptional, IsString, MaxLength, Min } from 'class-validator';

export class CompleteUploadDto {
  @IsOptional()
  @IsString()
  @MaxLength(255)
  etag?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  sizeBytes?: number;
}
