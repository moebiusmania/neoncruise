/// <reference types="bun" />
import { describe, expect, test } from 'bun:test';
import { sanitize } from './settings';

describe('sanitize', () => {
  test('falls back to defaults for garbage', () => {
    const d = sanitize(null);
    expect(sanitize('nope')).toEqual(d);
    expect(sanitize({ volume: 'loud', scan: 'yes', extra: 1 })).toEqual(d);
  });

  test('keeps valid values and clamps volume', () => {
    const s = sanitize({ station: 'ebsm', volume: 7, hiss: true, scan: false });
    expect(s).toMatchObject({ station: 'ebsm', volume: 1, hiss: true, scan: false });
    expect(sanitize({ volume: -3 }).volume).toBe(0);
    expect(sanitize({ volume: Number.NaN }).volume).toBe(sanitize(null).volume);
  });

  test('ignores prototype keys', () => {
    const s = sanitize(JSON.parse('{"__proto__": {"polluted": true}, "volume": 0.5}'));
    expect(s.volume).toBe(0.5);
    expect(({} as Record<string, unknown>).polluted).toBeUndefined();
  });
});
