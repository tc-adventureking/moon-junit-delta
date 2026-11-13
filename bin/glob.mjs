// Python glob's non-recursive grammar, including hidden-file and [] rules.
// Matching uses bounded dynamic programming, with no regular-expression backtracking.
import { opendirSync, lstatSync, statSync } from 'node:fs';
import path from 'node:path';

const device = (value) => process.platform === 'win32' && /^[\\/]{2}\?[\\/]/.test(value);
// Keep exact device paths exact. Other device spellings enter Win32's normal
// device namespace; Windows, rather than a hand-written trim, resolves them.
const fsPath = (value) => {
  if (!device(value)) return value;
  if (value.startsWith('\\\\?\\')) {
    if (value.includes('/') || value.slice(4).split('\\').some(part => part === '.' || part === '..')) throw new Error('invalid exact device path');
    return value;
  }
  return '\\\\.\\' + value.slice(4).replaceAll('/', '\\');
};
export { fsPath as filesystemPath };
const magic = (value) => /[*?[]/.test(value);
const exists = (value) => { try { lstatSync(fsPath(value)); return true; } catch { return false; } };
const directory = (value) => {
  try { return statSync(fsPath(value)).isDirectory(); }
  catch (error) {
    // libuv's stat drops the separator of some device roots and reports
    // EISDIR. Opening the directory validates that root without listing it.
    if (error.code !== 'EISDIR') return false;
    try { const handle = opendirSync(fsPath(value)); handle.closeSync(); return true; }
    catch { return false; }
  }
};
const join = (base, name) => !base ? name : (process.platform === 'win32' && /^[a-z]:$/i.test(base)) ? base + name : (base.endsWith(path.sep) || (process.platform === 'win32' && base.endsWith('/'))) ? base + name : base + path.sep + name;

export function matchName(name, pattern) {
  if (process.platform === 'win32') { name = name.toLowerCase(); pattern = pattern.toLowerCase(); }
  const chars = Array.from(pattern), input = Array.from(name), tokens = [];
  for (let i = 0; i < chars.length; i++) {
    const ch = chars[i];
    if (ch === '*') { if (tokens.at(-1)?.kind !== '*') tokens.push({ kind: '*' }); }
    else if (ch === '?') tokens.push({ kind: '?' });
    else if (ch === '[') {
      let end = i + 1;
      const negative = chars[end] === '!';
      if (negative) end++;
      if (chars[end] === ']') end++;
      while (end < chars.length && chars[end] !== ']') end++;
      if (end === chars.length) { tokens.push({ kind: '=', value: ch }); continue; }
      const ranges = [], singles = [];
      for (let j = i + 1 + Number(negative); j < end; j++) {
        if (j + 2 < end && chars[j + 1] === '-') {
          const low = chars[j].codePointAt(0), high = chars[j + 2].codePointAt(0);
          if (low <= high) ranges.push([low, high]);
          j += 2;
        } else singles.push(chars[j]);
      }
      tokens.push({ kind: '[]', ranges, singles, negative });
      i = end;
    } else tokens.push({ kind: '=', value: ch });
  }
  let previous = new Uint8Array(input.length + 1);
  previous[0] = 1;
  for (const token of tokens) {
    const next = new Uint8Array(input.length + 1);
    if (token.kind === '*') {
      next[0] = previous[0];
      for (let j = 1; j <= input.length; j++) next[j] = previous[j] || next[j - 1];
    } else {
      for (let j = 1; j <= input.length; j++) {
        let matches = token.kind === '?' || (token.kind === '=' && input[j - 1] === token.value);
        if (token.kind === '[]') {
          const code = input[j - 1].codePointAt(0);
          matches = token.singles.includes(input[j - 1]) || token.ranges.some(([a, b]) => a <= code && code <= b);
          if (token.negative) matches = !matches;
        }
        next[j] = previous[j - 1] && matches;
      }
    }
    previous = next;
  }
  return Boolean(previous[input.length]);
}

// Find the unchanged root boundary before splitting the final component.
// Unlike path.dirname, Windows split keeps UNC/device root separators and
// drive-relative roots. This also supplies a stable recursion stopping point.
function splitPattern(value) {
  if (process.platform !== 'win32') {
    const cut = value.lastIndexOf('/') + 1;
    const head = value.slice(0, cut);
    return [head && !/^\/+$/u.test(head) ? head.replace(/\/+$/u, '') : head, value.slice(cut)];
  }
  const native = value.replaceAll('/', '\\');
  let root = 0;
  if (native.startsWith('\\\\')) {
    const start = native.slice(0, 8).toUpperCase() === '\\\\?\\UNC\\' ? 8 : 2;
    const first = native.indexOf('\\', start);
    const next = first < 0 ? -1 : native.indexOf('\\', first + 1);
    root = next < 0 ? value.length : next + 1;
  } else if (native[1] === ':') root = native[2] === '\\' ? 3 : 2;
  else if (native.startsWith('\\')) root = 1;
  const tail = value.slice(root);
  const cut = Math.max(tail.lastIndexOf('/'), tail.lastIndexOf('\\')) + 1;
  return [value.slice(0, root) + tail.slice(0, cut).replace(/[\\/]+$/u, ''), tail.slice(cut)];
}

function expand(pattern, onlyDirectories) {
  const [parent, basename] = splitPattern(pattern);
  if (!magic(pattern)) return (basename ? exists(pattern) : directory(parent)) ? [pattern] : [];
  const parents = parent && parent !== pattern && magic(parent) ? expand(parent, true) : [parent];
  const result = [];
  for (const base of parents) {
    if (!magic(basename)) {
      if (basename ? exists(join(base, basename)) : directory(base)) result.push(join(base, basename));
      continue;
    }
    let handle;
    try {
      handle = opendirSync(fsPath(base || '.'));
      let entry;
      while ((entry = handle.readSync()) !== null) {
        if (entry.name.startsWith('.') && !basename.startsWith('.')) continue;
        if (onlyDirectories && !directory(join(base, entry.name))) continue;
        if (matchName(entry.name, basename)) result.push(join(base, entry.name));
      }
    } catch { continue; }
    finally { if (handle) handle.closeSync(); }
  }
  return result;
}

export function expandGlob(pattern) {
  return pattern ? expand(pattern, false) : [];
}
