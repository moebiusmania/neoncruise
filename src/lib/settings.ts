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

function load(): Settings {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) return { ...defaults, ...JSON.parse(raw) };
  } catch {
    /* storage unavailable */
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

effect(() => {
  const value = settings.value;
  try {
    localStorage.setItem(KEY, JSON.stringify(value));
  } catch {
    /* storage unavailable */
  }
});
