import { Module } from '@nestjs/common';
import { MatchModule } from '../match/match.module';
import { PubsubModule } from '../runtime/pubsub.module';
import { ShopService } from './shop.service';

@Module({
  imports: [MatchModule, PubsubModule],
  providers: [ShopService],
  exports: [ShopService],
})
export class ShopModule {}
