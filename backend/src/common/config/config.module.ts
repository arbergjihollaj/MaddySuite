import { Global, Module } from '@nestjs/common';
import { getEnv } from './env';

@Global()
@Module({
  providers: [
    {
      provide: 'ENV',
      useFactory: () => getEnv(),
    },
  ],
  exports: ['ENV'],
})
export class AppConfigModule {}
