import { Injectable } from '@nestjs/common';

@Injectable()
export class HealthRepository {
  ping() {
    return true;
  }
}
