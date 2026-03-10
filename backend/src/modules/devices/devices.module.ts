import { Module } from '@nestjs/common';
import { DevicesController } from './controller/devices.controller';
import { DevicesRepository } from './repository/devices.repository';
import { DevicesService } from './service/devices.service';

@Module({
  controllers: [DevicesController],
  providers: [DevicesRepository, DevicesService],
  exports: [DevicesRepository, DevicesService],
})
export class DevicesModule {}
