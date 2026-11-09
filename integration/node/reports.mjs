import { test } from 'node:test';
import assert from 'node:assert/strict';
const candidate = process.env.DELTA_STAGE === 'candidate';
test('stable', () => assert.equal(2 + 2, 4));
test('new failure 参数😀', () => assert.equal(candidate, false));
test('fixed failure', () => assert.equal(candidate, true));
test('skipped', { skip: 'intentional skip' }, () => {});
