// Internal runtime: node bin/run.mjs COMPILED_ENTRY [arguments...]
import { openSync, closeSync, readSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

process.stdout.on('error', () => { process.exitCode = 2; });
process.stderr.on('error', () => { process.exitCode = 2; });
globalThis.__junitDeltaRead = (path) => {
  let fd;
  try {
    fd = path === '-' ? 0 : openSync(path, 'r');
    const chunks = [];
    let size = 0;
    const cap = 20_000_000;
    while (true) {
      const chunk = Buffer.allocUnsafe(65536);
      const count = readSync(fd, chunk, 0, chunk.length, null);
      if (count === 0) break;
      size += count;
      if (size > cap) throw new Error(`input exceeds ${cap} bytes`);
      chunks.push(chunk.subarray(0, count));
    }
    const text = new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks));
    return JSON.stringify({ ok: true, text });
  } catch (error) {
    return JSON.stringify({ ok: false, error: `${path}: ${error.message}` });
  } finally {
    if (fd !== undefined && fd !== 0) closeSync(fd);
  }
};
try {
  const entry = process.argv[2];
  process.argv.splice(1, 1);
  await import(pathToFileURL(entry).href);
} catch (error) {
  process.stderr.write(`junit-delta: runtime error: ${error.message}\n`);
  process.exitCode = 2;
}
