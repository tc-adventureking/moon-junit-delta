import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
export function readVersion(root) {
  const manifest=join(root,'MANIFEST.json');
  const version=existsSync(manifest)?JSON.parse(readFileSync(manifest,'utf8')).version:readFileSync(join(root,'moon.mod'),'utf8').match(/^version = "(\d+\.\d+\.\d+)"$/m)?.[1];
  if (!/^\d+\.\d+\.\d+$/.test(version??'')) throw Error('Invalid release version');
  return version;
}
