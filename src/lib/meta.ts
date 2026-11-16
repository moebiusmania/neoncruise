import { batch, signal } from '@preact/signals';
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
/** Upper bound for strings coming off the network, so a bad frame can't bloat the UI or memory. */
const TEXT_MAX = 300;
const STATUS_TIMEOUT_MS = 10_000;
const known = new Set(STATIONS.map((s) => s.id));

export const tracks = signal<Record<string, Track>>({});
export const history = signal<Record<string, Track[]>>({});
export const listeners = signal<Record<string, number>>({});
export const metaOnline = signal(false);

const same = (a: Track, b: Track) =>
  (a.id && b.id && a.id === b.id) ||
  (a.title.toLowerCase() === b.title.toLowerCase() && a.artist.toLowerCase() === b.artist.toLowerCase());

const text = (v: unknown) => (typeof v === 'string' ? v.slice(0, TEXT_MAX) : '');

/** Validate one SSE item; the feed is third-party data, so never trust its shape. */
function toTrack(it: unknown): [string, Track] | null {
  if (!it || typeof it !== 'object') return null;
  const m = it as Partial<Record<keyof MetaEvent, unknown>>;
  if (typeof m.station !== 'string' || !known.has(m.station)) return null;
  const title = text(m.title);
  const artist = text(m.artist);
  if (!title && !artist) return null;
  return [
    m.station,
    {
      title,
      artist,
      at: typeof m.at === 'number' && Number.isFinite(m.at) ? m.at : undefined,
      id: typeof m.track_id === 'string' ? m.track_id : undefined,
    },
  ];
}

function pushTrack(station: string, t: Track) {
  const cur = tracks.peek()[station];
  if (cur && same(cur, t) && cur.at) return;
  // One notification for both signals instead of two render passes.
  batch(() => {
    tracks.value = { ...tracks.peek(), [station]: t };
    const list = (history.peek()[station] ?? []).filter((x) => !same(x, t));
    history.value = { ...history.peek(), [station]: [t, ...list].slice(0, HISTORY_MAX) };
  });
}

function splitTitle(s: string): Track {
  const i = s.indexOf(' - ');
  return i > 0
    ? { artist: text(s.slice(0, i).trim()), title: text(s.slice(i + 3).trim()) }
    : { artist: '', title: text(s.trim()) };
}

async function fetchStatus(seed: boolean) {
  try {
    const res = await fetch(STATUS_URL, { cache: 'no-store', signal: AbortSignal.timeout(STATUS_TIMEOUT_MS) });
    if (!res.ok) return;
    const json = await res.json();
    const sources: any[] = [].concat(json?.icestats?.source ?? []);
    const nextHistory = { ...history.peek() };
    const nextTracks = { ...tracks.peek() };
    const counts: Record<string, number> = {};
    for (const src of sources) {
      const m = /\/([\w-]+)\.(mp3|ogg|m4a)$/.exec(src.listenurl ?? '');
      if (!m || !known.has(m[1])) continue;
      const id = m[1];
      counts[id] = (counts[id] ?? 0) + (Number(src.listeners) || 0);
      if (seed && m[2] === 'mp3') {
        const list: Track[] = (src.playlist?.trackList ?? [])
          .map((x: { title?: unknown }) => splitTitle(text(x?.title)))
          .filter((t: Track) => t.title)
          .reverse();
        if (list.length && !nextHistory[id]?.length) nextHistory[id] = list.slice(0, HISTORY_MAX);
        const artist = text(src.artist);
        const title = text(src.title);
        if (!nextTracks[id] && (artist || title)) nextTracks[id] = artist ? { artist, title } : splitTitle(title);
      }
    }
    batch(() => {
      listeners.value = counts;
      if (seed) {
        history.value = nextHistory;
        tracks.value = nextTracks;
      }
    });
  } catch {
    /* status is best-effort */
  }
}

let started = false;
let metaRetries = 0;

/**
 * EventSource retries transient drops by itself, but gives up for good (readyState CLOSED)
 * on an HTTP error or a wrong content type. Reconnect from scratch in that case, with backoff.
 */
function connectMeta() {
  const es = new EventSource(META_URL);
  es.onopen = () => {
    metaRetries = 0;
    metaOnline.value = true;
  };
  es.onerror = () => {
    metaOnline.value = false;
    if (es.readyState !== EventSource.CLOSED) return;
    es.close();
    const delay = Math.min(60_000, 2000 * 2 ** metaRetries++);
    setTimeout(connectMeta, delay);
  };
  es.onmessage = (ev) => {
    metaOnline.value = true;
    let items: unknown;
    try {
      items = JSON.parse(ev.data);
    } catch {
      return; /* ignore malformed frames */
    }
    if (!Array.isArray(items)) return;
    for (const it of items) {
      const parsed = toTrack(it);
      if (parsed) pushTrack(parsed[0], parsed[1]);
    }
  };
}

export function startMeta() {
  if (started || typeof window === 'undefined') return;
  started = true;

  connectMeta();
  fetchStatus(true);
  setInterval(() => document.visibilityState === 'visible' && fetchStatus(false), 60_000);
}
