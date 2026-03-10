import { Module } from '@nestjs/common';
import { AttachmentsController } from './controller/attachments.controller';
import { AttachmentsRepository } from './repository/attachments.repository';
import { AttachmentsService } from './service/attachments.service';

@Module({
  controllers: [AttachmentsController],
  providers: [AttachmentsRepository, AttachmentsService],
  exports: [AttachmentsRepository, AttachmentsService],
})
export class AttachmentsModule {}
