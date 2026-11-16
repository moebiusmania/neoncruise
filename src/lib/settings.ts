import { effect, signal } from '@preact/signals';

export interface Settings {
  station: string;
  volume: number;
  scan: boolean;
  flicker: boolean;
  noise: boolean;
  /** Route audio through Web Audio for the spectrum + beat-synced visuals. */
  reactive: boolean;
  /** Mix a faint analog tape hiss over the stream. */
  hiss: boolean;
}

const KEY = 'neoncruise:settings:v1';

/** iOS suspends a Web Audio graph when the app is backgrounded, which would stop the radio. */
export const isIOS =
  typeof navigator !== 'undefined' &&
  (/iP(hone|ad|od)/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1));

const defaults: Settings = {
  station: 'nightride',
  volume: 0.85,
  scan: true,
  flicker: true,
  noise: true,
  reactive: !isIOS,
  hiss: false,
};

/**
 * Storage is user-controlled (and shared with anything else on the origin), so only accept
 * known keys with the right type. A bad `volume` (e.g. NaN) would otherwise make
 * `audio.volume = …` throw and break player init.
 */
function sanitize(raw: unknown): Settings {
  const out = { ...defaults };
  if (!raw || typeof raw !== 'object') return out;
  const r = raw as Record<string, unknown>;
  if (typeof r.station === 'string') out.station = r.station;
  if (typeof r.volume === 'number' && Number.isFinite(r.volume)) out.volume = Math.max(0, Math.min(1, r.volume));
  for (const k of ['scan', 'flicker', 'noise', 'reactive', 'hiss'] as const) {
    if (typeof r[k] === 'boolean') out[k] = r[k];
  }
  return out;
}

function load(): Settings {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) return sanitize(JSON.parse(raw));
  } catch {
    /* storage unavailable or corrupt */
  }
  return defaults;
}

export const settings = signal<Settings>(load());

export function setSetting<K extends keyof Settings>(key: K, value: Settings[K]) {
  settings.value = { ...settings.value, [key]: value };
}

export function toggleSetting(key: 'scan' | 'flicker' | 'noise' | 'reactive' | 'hiss') {
  setSetting(key, !settings.value[key]);
}

// localStorage is synchronous and dragging the volume slider fires ~60 updates a second,
// so coalesce writes and flush whatever is pending when the page is hidden.
let saveTimer = 0;
function persist() {
  clearTimeout(saveTimer);
  saveTimer = 0;
  try {
    localStorage.setItem(KEY, JSON.stringify(settings.peek()));
  } catch {
    /* storage unavailable */
  }
}

let first = true;
effect(() => {
  settings.value;
  if (first) {
    first = false;
    return;
  }
  clearTimeout(saveTimer);
  saveTimer = setTimeout(persist, 250) as unknown as number;
});

if (typeof document !== 'undefined') {
  document.addEventListener('visibilitychange', () => document.visibilityState === 'hidden' && saveTimer && persist());
}
