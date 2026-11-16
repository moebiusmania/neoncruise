/// <reference types="bun" />
import { describe, expect, test } from 'bun:test';
import { same, splitTitle, toTrack } from './meta';

describe('toTrack', () => {
  test('accepts a valid item for a known station', () => {
    expect(toTrack({ station: 'nightride', title: 'T', artist: 'A', at: 5, track_id: 'x' })).toEqual([
      'nightride',
      { title: 'T', artist: 'A', at: 5, id: 'x' },
    ]);
  });

  test('rejects unknown stations, wrong shapes and empty tracks', () => {
    expect(toTrack({ station: 'nope', title: 'T' })).toBeNull();
    expect(toTrack(null)).toBeNull();
    expect(toTrack('nightride')).toBeNull();
    expect(toTrack({ station: 'nightride', title: '', artist: '' })).toBeNull();
  });

  test('drops non-string fields and non-finite timestamps, caps long strings', () => {
    const r = toTrack({ station: 'ebsm', title: 42, artist: 'x'.repeat(1000), at: Number.NaN, track_id: 7 });
    expect(r?.[1]).toEqual({ title: '', artist: 'x'.repeat(300), at: undefined, id: undefined });
  });
});

describe('splitTitle', () => {
  test('splits on the first " - "', () => {
    expect(splitTitle('Artist - Song - Remix')).toEqual({ artist: 'Artist', title: 'Song - Remix' });
  });
  test('keeps a title with no separator', () => {
    expect(splitTitle('  Just a title ')).toEqual({ artist: '', title: 'Just a title' });
  });
});

describe('same', () => {
  test('matches by id, or by case-insensitive title and artist', () => {
    expect(same({ title: 'a', artist: 'b', id: '1' }, { title: 'x', artist: 'y', id: '1' })).toBe(true);
    expect(same({ title: 'Song', artist: 'Band' }, { title: 'SONG', artist: 'band' })).toBe(true);
    expect(same({ title: 'Song', artist: 'Band' }, { title: 'Other', artist: 'Band' })).toBe(false);
  });
});
