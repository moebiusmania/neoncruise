import { computed, effect, signal } from '@preact/signals';
import { STATIONS, streamUrl, wrapIndex } from './stations';
import { isIOS, setSetting, settings } from './settings';
import { tracks } from './meta';

export type Status = 'idle' | 'loading' | 'playing' | 'paused' | 'error';

const initialIdx = Math.max(
  0,
  STATIONS.findIndex((s) => s.id === settings.peek().station),
);

export const stationIdx = signal(initialIdx);
export const station = computed(() => STATIONS[stationIdx.value]);
export const status = signal<Status>('idle');
/** What the user asked for; `status` is what the stream is actually doing. */
export const wantPlay = signal(false);
export const now = signal(Date.now());
export const sleepEnd = signal(0);
export const sleepMin = signal(0);
/** Timestamp of the last station switch, drives the static burst. */
export const burstAt = signal(0);
/** Whether this device lets the page change the media element volume (iOS doesn't). */
export const volumeControllable = signal(true);

let audio: HTMLAudioElement | null = null;
let ctx: AudioContext | null = null;
let analyser: AnalyserNode | null = null;
let hissGain: GainNode | null = null;
let noiseBuf: AudioBuffer | null = null;
let graphed = new WeakSet<HTMLAudioElement>();
let retries = 0;
let retryTimer = 0;
let fade = 1;
/** True while a new src is loading, so the element's implicit pause isn't read as the user's. */
let switching = false;

/* ------------------------------------------------------------------ audio element */

function createAudio() {
  const a = new Audio();
  a.preload = 'none';
  a.crossOrigin = 'anonymous';
  a.setAttribute('playsinline', '');
  a.volume = settings.peek().volume;

  a.addEventListener('playing', () => {
    retries = 0;
    switching = false;
    status.value = 'playing';
  });
  a.addEventListener('waiting', () => wantPlay.peek() && (status.value = 'loading'));
  a.addEventListener('stalled', () => wantPlay.peek() && (status.value = 'loading'));
  a.addEventListener('pause', () => {
    // A pause we didn't ask for (headphones unplugged, OS interruption).
    if (wantPlay.peek() && !switching && a.getAttribute('src') && !a.ended) {
      wantPlay.value = false;
      status.value = 'paused';
    }
  });
  a.addEventListener('ended', () => wantPlay.peek() && scheduleRetry());
  a.addEventListener('error', () => {
    if (!wantPlay.peek() || !a.getAttribute('src')) return;
    scheduleRetry();
  });
  return a;
}

function ensureAudio() {
  if (!audio) {
    audio = createAudio();
    // Probe whether volume can be changed (iOS ignores it and reads back 1).
    const probe = new Audio();
    probe.volume = 0.5;
    volumeControllable.value = !isIOS && probe.volume === 0.5;
  }
  return audio;
}

function scheduleRetry() {
  clearTimeout(retryTimer);
  if (retries >= 6) {
    status.value = 'error';
    wantPlay.value = false;
    return;
  }
  status.value = 'loading';
  const delay = Math.min(8000, 600 * 2 ** retries++);
  retryTimer = window.setTimeout(() => wantPlay.peek() && startStream(), delay);
}

/* ------------------------------------------------------------------ web audio graph */

function ensureGraph(a: HTMLAudioElement) {
  if (!settings.peek().reactive) return;
  try {
    if (!ctx) {
      const AC = window.AudioContext || (window as any).webkitAudioContext;
      ctx = new AC();
      analyser = ctx.createAnalyser();
      analyser.fftSize = 512;
      analyser.smoothingTimeConstant = 0.78;
      analyser.connect(ctx.destination);
    }
    if (!graphed.has(a)) {
      ctx.createMediaElementSource(a).connect(analyser!);
      graphed.add(a);
    }
    if (ctx.state === 'suspended') ctx.resume();
  } catch (err) {
    console.warn('[neoncruise] Web Audio unavailable, visuals will be simulated', err);
  }
}

function noiseBuffer(c: AudioContext) {
  if (noiseBuf) return noiseBuf;
  const len = c.sampleRate * 2;
  noiseBuf = c.createBuffer(1, len, c.sampleRate);
  const d = noiseBuf.getChannelData(0);
  for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
  return noiseBuf;
}

function ensureHiss() {
  if (!ctx || hissGain) return;
  const src = ctx.createBufferSource();
  src.buffer = noiseBuffer(ctx);
  src.loop = true;
  const hp = ctx.createBiquadFilter();
  hp.type = 'highpass';
  hp.frequency.value = 3800;
  const lp = ctx.createBiquadFilter();
  lp.type = 'lowpass';
  lp.frequency.value = 11000;
  hissGain = ctx.createGain();
  hissGain.gain.value = 0;
  src.connect(hp).connect(lp).connect(hissGain).connect(ctx.destination);
  src.start();
}

/** Short burst of radio static when changing tapes. */
function staticBurst() {
  if (!ctx || ctx.state !== 'running') return;
  const src = ctx.createBufferSource();
  src.buffer = noiseBuffer(ctx);
  const bp = ctx.createBiquadFilter();
  bp.type = 'bandpass';
  bp.frequency.value = 2400;
  bp.Q.value = 0.6;
  const g = ctx.createGain();
  const t = ctx.currentTime;
  const vol = 0.09 * settings.peek().volume;
  g.gain.setValueAtTime(vol, t);
  g.gain.exponentialRampToValueAtTime(0.0001, t + 0.45);
  src.connect(bp).connect(g).connect(ctx.destination);
  src.start(t, Math.random());
  src.stop(t + 0.5);
}

export function getAnalyser() {
  return analyser && ctx?.state === 'running' && status.peek() === 'playing' ? analyser : null;
}

/* ------------------------------------------------------------------ transport */

function startStream() {
  const a = ensureAudio();
  ensureGraph(a);
  switching = true;
  a.src = `${streamUrl(station.peek().id)}?nc=${Date.now()}`;
  a.play().catch((err: DOMException) => {
    if (err.name === 'NotAllowedError') {
      wantPlay.value = false;
      status.value = 'paused';
    } else if (err.name !== 'AbortError') {
      scheduleRetry();
    }
  });
}

export function play() {
  clearTimeout(retryTimer);
  retries = 0;
  fade = 1;
  wantPlay.value = true;
  status.value = 'loading';
  startStream();
}

export function pause() {
  clearTimeout(retryTimer);
  wantPlay.value = false;
  status.value = 'paused';
  if (audio) {
    audio.pause();
    // Drop the live buffer so resuming jumps back to "now" instead of stale audio.
    audio.removeAttribute('src');
    audio.load();
  }
}

export function togglePlay() {
  wantPlay.peek() ? pause() : play();
}

export function tune(i: number) {
  const next = wrapIndex(i);
  if (next === stationIdx.peek() && wantPlay.peek()) return;
  stationIdx.value = next;
  setSetting('station', STATIONS[next].id);
  burstAt.value = Date.now();
  if (wantPlay.peek()) {
    staticBurst();
    play();
  }
}

export const tuneBy = (d: number) => tune(stationIdx.peek() + d);

/** Change tape and start playing it (from a user gesture). */
export function insert(i: number) {
  const next = wrapIndex(i);
  if (next !== stationIdx.peek()) {
    stationIdx.value = next;
    setSetting('station', STATIONS[next].id);
    burstAt.value = Date.now();
    staticBurst();
  }
  play();
}

/* ------------------------------------------------------------------ sleep timer */

export function setSleep(min: number) {
  sleepMin.value = min;
  sleepEnd.value = min ? Date.now() + min * 60_000 : 0;
  fade = 1;
  applyVolume();
}

const FADE_SECS = 12;

function tick() {
  const t = Date.now();
  now.value = t;
  const end = sleepEnd.peek();
  if (!end) return;
  const left = (end - t) / 1000;
  if (left <= 0) {
    setSleep(0);
    pause();
  } else if (left < FADE_SECS && wantPlay.peek()) {
    fade = left / FADE_SECS;
    applyVolume();
  }
}

/* ------------------------------------------------------------------ settings wiring */

function applyVolume() {
  const v = settings.peek().volume * fade;
  if (audio) audio.volume = Math.max(0, Math.min(1, v));
}

export function setVolume(v: number) {
  setSetting('volume', Math.max(0, Math.min(1, v)));
}

let prevReactive = settings.peek().reactive;

function initEffects() {
  effect(() => {
    settings.value.volume;
    applyVolume();
  });

  // Toggling audio-reactive needs a fresh <audio>: a MediaElementSource can't be unbound.
  effect(() => {
    const r = settings.value.reactive;
    if (r === prevReactive) return;
    prevReactive = r;
    if (!audio) return;
    const was = wantPlay.peek();
    audio.pause();
    audio.removeAttribute('src');
    audio.load();
    audio = createAudio();
    graphed = new WeakSet();
    if (was) play();
  });

  effect(() => {
    const on = settings.value.hiss && settings.value.reactive && status.value === 'playing';
    if (on) ensureHiss();
    if (hissGain && ctx) hissGain.gain.setTargetAtTime(on ? 0.018 * settings.value.volume : 0, ctx.currentTime, 0.4);
  });

  if ('mediaSession' in navigator) {
    const ms = navigator.mediaSession;
    const base = import.meta.env.BASE_URL.replace(/\/?$/, '/');
    const icon = (s: number) => ({ src: `${base}icons/icon-${s}.png`, sizes: `${s}x${s}`, type: 'image/png' });
    effect(() => {
      const st = station.value;
      const t = tracks.value[st.id];
      ms.metadata = new MediaMetadata({
        title: t?.title || `${st.name} FM`,
        artist: t?.artist || st.tag,
        album: `${st.name} · Nightride FM`,
        artwork: [icon(192), icon(512)],
      });
    });
    effect(() => {
      ms.playbackState = wantPlay.value ? 'playing' : status.value === 'idle' ? 'none' : 'paused';
    });
    const set = (a: MediaSessionAction, fn: () => void) => {
      try {
        ms.setActionHandler(a, fn);
      } catch {
        /* unsupported action */
      }
    };
    set('play', play);
    set('pause', pause);
    set('stop', pause);
    set('nexttrack', () => tuneBy(1));
    set('previoustrack', () => tuneBy(-1));
  }

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && ctx?.state === 'suspended' && wantPlay.peek()) ctx.resume();
  });

  setInterval(tick, 1000);
}

let inited = false;
export function initPlayer() {
  if (inited || typeof window === 'undefined') return;
  inited = true;
  ensureAudio();
  initEffects();
}

/* ------------------------------------------------------------------ helpers */

export const fmt = (secs: number) => {
  const s = Math.max(0, Math.floor(secs));
  const h = Math.floor(s / 3600);
  const mm = String(Math.floor((s % 3600) / 60)).padStart(2, '0');
  const ss = String(s % 60).padStart(2, '0');
  return h ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
};

export const statusLabel = computed(() => {
  const st = status.value;
  if (st === 'loading') return 'TUNING';
  if (st === 'error') return 'NO SIGNAL';
  if (st === 'playing') {
    if (sleepEnd.value) return `SLEEP ${Math.max(1, Math.ceil((sleepEnd.value - now.value) / 60000))}M`;
    return 'ON AIR';
  }
  return st === 'idle' ? 'STANDBY' : 'PAUSED';
});
