// Test-only process wrapper. The measurement path is supplied by the test runner.
import { writeFileSync } from 'node:fs';
process.on('exit', () => {
  if (process.env.JUNIT_DELTA_MEASURE_PATH) {
    writeFileSync(process.env.JUNIT_DELTA_MEASURE_PATH, JSON.stringify({max_rss_kib:process.resourceUsage().maxRSS}));
  }
});
await import('../bin/run.mjs');
