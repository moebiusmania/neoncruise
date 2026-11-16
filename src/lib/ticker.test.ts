/// <reference types="bun" />
import { describe, expect, test } from 'bun:test';
import { approachHue } from './ticker';
import { fmt } from './player';

describe('approachHue', () => {
  test('takes the short way round 360', () => {
    expect(approachHue(350, 10, 0.5)).toBeCloseTo(0);
    expect(approachHue(10, 350, 0.5)).toBeCloseTo(0);
  });
  test('stays in [0, 360)', () => {
    const h = approachHue(355, 25, 1);
    expect(h).toBeGreaterThanOrEqual(0);
    expect(h).toBeLessThan(360);
    expect(h).toBeCloseTo(25);
  });
});

describe('fmt', () => {
  test('formats minutes and hours, clamps negatives', () => {
    expect(fmt(65.9)).toBe('01:05');
    expect(fmt(3725)).toBe('1:02:05');
    expect(fmt(-4)).toBe('00:00');
  });
});
