// Internal runtime: node bin/run.mjs COMPILED_ENTRY [arguments...]
import { openSync, closeSync, readSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { expandGlob, filesystemPath } from './glob.mjs';

process.stdout.on('error', () => { process.exitCode = 2; });
process.stderr.on('error', () => { process.exitCode = 2; });
function readInput(path, report) {
  let fd;
  try {
    fd = path === '-' ? 0 : openSync(filesystemPath(path), 'r');
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
    const bytes = Buffer.concat(chunks);
    const utf8Bom = bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf;
    const content = report && utf8Bom ? bytes.subarray(3) : bytes;
    let encoding = 'utf-8';
    if (report) {
      if ((bytes[0] === 0xff && bytes[1] === 0xfe) || (bytes[0] === 60 && bytes[1] === 0)) encoding = 'utf-16le';
      else if ((bytes[0] === 0xfe && bytes[1] === 0xff) || (bytes[0] === 0 && bytes[1] === 60)) encoding = 'utf-16be';
      else {
        const declarationEnd = content.subarray(0, 5).toString('ascii') === '<?xml' ? content.indexOf('?>') : -1;
        const declaration = declarationEnd < 0 ? undefined : content.subarray(0, declarationEnd + 2).toString('latin1').match(/^<\?xml\s[^?]*\?>/);
        const label = declaration?.[0].match(/\bencoding\s*=\s*['"]([^'"]+)['"]/i)?.[1];
        if (label) encoding = label;
      }
    }
    const label = encoding.toLowerCase();
    let text;
    if (report && ['iso-8859-1', 'iso8859-1', 'iso_8859-1', 'latin1', 'l1', 'csisolatin1', 'cp819', 'ibm819', 'iso-ir-100', 'iso-latin-1'].includes(label)) {
      text = content.toString('latin1');
    } else if (report && ['ascii', 'us-ascii', 'ansi_x3.4-1968', 'ansi_x3.4-1986', 'iso-ir-6', 'iso646-us', 'us', 'ibm367', 'cp367', 'csascii'].includes(label)) {
      if (content.some(byte => byte > 127)) throw new Error('non-ASCII byte in ASCII XML');
      text = content.toString('ascii');
    } else {
      const decoder = new TextDecoder(encoding, { fatal: true });
      // WHATWG accepts extra ISO/Latin aliases and maps them to Windows-1252.
      // Keep those labels restricted to the exact verified XML names above.
      if (report && decoder.encoding === 'windows-1252' && !['windows-1252', 'cp1252'].includes(label)) throw new Error(`unsupported XML encoding: ${encoding}`);
      if (report && decoder.encoding === 'windows-1252' && content.some(byte => [0x81, 0x8d, 0x8f, 0x90, 0x9d].includes(byte))) throw new Error('undefined byte in Windows-1252 XML');
      text = decoder.decode(content);
    }
    if (report && /^utf-16/i.test(encoding)) text = '\ufeff' + text;
    return JSON.stringify({ ok: true, text });
  } catch (error) {
    return JSON.stringify({ ok: false, error: `${path}: ${error.message}` });
  } finally {
    if (fd !== undefined && fd !== 0) closeSync(fd);
  }
}
globalThis.__junitDeltaRead = (path, report = false) => readInput(path, report);
globalThis.__junitDeltaWrite = (path, text) => {
  try { writeFileSync(filesystemPath(path), text, 'utf8'); return JSON.stringify({ ok: true }); }
  catch (error) { return JSON.stringify({ ok: false, error: `${path}: ${error.message}` }); }
};
globalThis.__junitDeltaGlob = (pattern) => JSON.stringify(expandGlob(pattern));
try {
  const entry = process.argv[2];
  process.argv.splice(1, 1);
  await import(pathToFileURL(entry).href);
} catch (error) {
  process.stderr.write(`junit-delta: runtime error: ${error.message}\n`);
  process.exitCode = 2;
}
