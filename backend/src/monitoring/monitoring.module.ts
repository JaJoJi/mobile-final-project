import { Module } from '@nestjs/common';
import { OperationalMetricsController } from './operational-metrics.controller';

@Module({ controllers: [OperationalMetricsController] })
export class MonitoringModule {}
