import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { CurrentUser } from '@/modules/auth/service/current-user.decorator';
import { AuthGuard } from '@/modules/auth/service/auth.guard';
import { RequestUploadUrlDto } from '../dto/request-upload-url.dto';
import { CompleteUploadDto } from '../dto/complete-upload.dto';
import { AttachmentsService } from '../service/attachments.service';

@Controller('attachments')
@UseGuards(AuthGuard)
export class AttachmentsController {
  constructor(private readonly attachmentsService: AttachmentsService) {}

  @Get()
  list(@CurrentUser() user: AuthenticatedUser) {
    return this.attachmentsService.list(user);
  }

  @Post('presign-upload')
  presignUpload(@CurrentUser() user: AuthenticatedUser, @Body() dto: RequestUploadUrlDto) {
    return this.attachmentsService.requestUploadUrl(user, dto);
  }

  @Post(':id/complete')
  complete(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
    @Body() dto: CompleteUploadDto,
  ) {
    return this.attachmentsService.completeUpload(user, id, dto);
  }

  @Get(':id/download-url')
  downloadUrl(@CurrentUser() user: AuthenticatedUser, @Param('id') id: string) {
    return this.attachmentsService.downloadUrl(user, id);
  }
}
