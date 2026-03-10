import { IsOptional, IsString } from 'class-validator';

export class StatsQueryDto {
  @IsOptional()
  @IsString()
  from?: string;

  @IsOptional()
  @IsString()
  to?: string;
}
