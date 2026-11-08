import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
describe('node fixture', () => {
  it('passes & keeps unicode 中文', () => assert.equal(2 + 2, 4));
  it.skip('planned test', () => {});
});
