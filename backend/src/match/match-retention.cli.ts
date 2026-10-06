import dataSource from '../data-source';
import { MatchRetentionService } from './match-retention.service';

async function main() {
  const apply = process.argv.includes('--apply');
  await dataSource.initialize();
  try {
    const report = await new MatchRetentionService(dataSource).run(!apply);
    console.log(JSON.stringify(report, null, 2));
    if (!apply) console.log('Dry run only. Add --apply to clear expired event payloads and delete expired match history.');
  } finally {
    await dataSource.destroy();
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
