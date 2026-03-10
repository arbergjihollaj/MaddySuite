import { Type } from 'class-transformer';
import { IsBoolean, IsOptional } from 'class-validator';

export class ListTasksQueryDto {
  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  includeDeleted?: boolean = false;
}
