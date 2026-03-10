import { IsEmail, IsOptional, IsString, IsUUID } from 'class-validator';

export class CreateUserDto {
  @IsUUID()
  id!: string;

  @IsOptional()
  @IsString()
  clerkUserId?: string;

  @IsOptional()
  @IsEmail()
  email?: string;
}
