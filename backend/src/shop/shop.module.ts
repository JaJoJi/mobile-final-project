import { Module } from '@nestjs/common';
import { MatchModule } from '../match/match.module';
import { WsModule } from '../ws/ws.module';
import { ShopService } from './shop.service';

@Module({
  imports: [MatchModule, WsModule],
  providers: [ShopService],
  exports: [ShopService],
})
export class ShopModule {}
