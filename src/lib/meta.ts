import { signal } from '@preact/signals';
import { META_URL, STATIONS, STATUS_URL } from './stations';

export interface Track {
  title: string;
  artist: string;
  /** Epoch ms when the track started, if known. */
  at?: number;
  id?: string;
}

interface MetaEvent {
  station: string;
  title: string;
  artist: string;
  track_id?: string;
  at?: number;
}

const HISTORY_MAX = 15;
const known = new Set(STATIONS.map((s) => s.id));

export const tracks = signal<Record<string, Track>>({});
export const history = signal<Record<string, Track[]>>({});
export const listeners = signal<Record<string, number>>({});
export const metaOnline = signal(false);

const same = (a: Track, b: Track) =>
  (a.id && b.id && a.id === b.id) ||
  (a.title.toLowerCase() === b.title.toLowerCase() && a.artist.toLowerCase() === b.artist.toLowerCase());

function pushTrack(station: string, t: Track) {
  const cur = tracks.value[station];
  if (cur && same(cur, t) && cur.at) return;
  tracks.value = { ...tracks.value, [station]: t };
  const list = (history.value[station] ?? []).filter((x) => !same(x, t));
  history.value = { ...history.value, [station]: [t, ...list].slice(0, HISTORY_MAX) };
}

function splitTitle(s: string): Track {
  const i = s.indexOf(' - ');
  return i > 0 ? { artist: s.slice(0, i).trim(), title: s.slice(i + 3).trim() } : { artist: '', title: s.trim() };
}

async function fetchStatus(seed: boolean) {
  try {
    const res = await fetch(STATUS_URL, { cache: 'no-store' });
    const json = await res.json();
    const sources: any[] = [].concat(json?.icestats?.source ?? []);
    const counts: Record<string, number> = {};
    for (const src of sources) {
      const m = /\/([\w-]+)\.(mp3|ogg|m4a)$/.exec(src.listenurl ?? '');
      if (!m || !known.has(m[1])) continue;
      const id = m[1];
      counts[id] = (counts[id] ?? 0) + (Number(src.listeners) || 0);
      if (seed && m[2] === 'mp3') {
        const list: Track[] = (src.playlist?.trackList ?? [])
          .map((x: { title?: string }) => splitTitle(x.title ?? ''))
          .filter((t: Track) => t.title)
          .reverse();
        if (list.length && !history.value[id]?.length) {
          history.value = { ...history.value, [id]: list.slice(0, HISTORY_MAX) };
        }
        if (!tracks.value[id] && (src.artist || src.title)) {
          const t = src.artist ? { artist: src.artist, title: src.title ?? '' } : splitTitle(src.title ?? '');
          tracks.value = { ...tracks.value, [id]: t };
        }
      }
    }
    listeners.value = counts;
  } catch {
    /* status is best-effort */
  }
}

let started = false;

export function startMeta() {
  if (started || typeof window === 'undefined') return;
  started = true;

  const es = new EventSource(META_URL);
  es.onopen = () => (metaOnline.value = true);
  es.onerror = () => (metaOnline.value = false);
  es.onmessage = (ev) => {
    metaOnline.value = true;
    try {
      const items: MetaEvent[] = JSON.parse(ev.data);
      for (const it of items) {
        if (!known.has(it.station)) continue;
        pushTrack(it.station, { title: it.title, artist: it.artist, at: it.at, id: it.track_id });
      }
    } catch {
      /* ignore malformed frames */
    }
  };

  fetchStatus(true);
  setInterval(() => document.visibilityState === 'visible' && fetchStatus(false), 60_000);
}
