import { getAnalyser, wantPlay } from './player';

/** Shared per-frame visual state, written once per frame and read by every canvas. */
export const vis = {
  /** Current (interpolated) scene hue. */
  hue: 350,
  /** 0..1 pulse that spikes on kicks (or a simulated 110 BPM beat). */
  beat: 0,
  /** 0..1 overall loudness. */
  level: 0,
  /** Frequency bins 0..255 (empty when not reactive). */
  bins: new Uint8Array(256) as Uint8Array<ArrayBuffer>,
  /** True when `bins` holds real audio data this frame. */
  live: false,
  t: 0,
  dt: 0,
};

type Sub = (t: number) => void;
const subs = new Set<Sub>();
let raf = 0;
let bassAvg = 0.2;
let last = 0;

const reducedMotion =
  typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches;
export const motionScale = reducedMotion ? 0.25 : 1;

function sample(t: number) {
  const an = getAnalyser();
  if (an) {
    if (vis.bins.length !== an.frequencyBinCount) vis.bins = new Uint8Array(an.frequencyBinCount);
    an.getByteFrequencyData(vis.bins);
    let bass = 0;
    for (let i = 1; i < 7; i++) bass += vis.bins[i];
    bass /= 6 * 255;
    let sum = 0;
    for (let i = 0; i < 96; i++) sum += vis.bins[i];
    vis.level = sum / (96 * 255);
    bassAvg += (bass - bassAvg) * 0.04;
    const kick = Math.max(0, (bass - bassAvg * 1.06) * 6);
    vis.beat = Math.max(vis.beat * 0.88, Math.min(1, kick));
    vis.live = true;
  } else {
    vis.live = false;
    const playing = wantPlay.peek();
    vis.beat = playing ? Math.pow(1 - ((t * 1.833) % 1), 3) : vis.beat * 0.9;
    vis.level += ((playing ? 0.35 : 0) - vis.level) * 0.05;
  }
}

function loop(ms: number) {
  const t = ms / 1000;
  vis.dt = Math.min(0.05, t - (last || t));
  vis.t = t;
  last = t;
  sample(t);
  for (const fn of subs) {
    try {
      fn(t);
    } catch (err) {
      console.error(err);
    }
  }
  raf = subs.size ? requestAnimationFrame(loop) : 0;
}

export function subscribe(fn: Sub) {
  subs.add(fn);
  if (!raf) raf = requestAnimationFrame(loop);
  return () => {
    subs.delete(fn);
  };
}

/** Shortest-path hue interpolation (wraps around 360). */
export function approachHue(from: number, to: number, k: number) {
  const d = ((to - from + 540) % 360) - 180;
  return (from + d * k + 360) % 360;
}

/** Fit a canvas backing store to its CSS box. Returns [ctx, width, height] in CSS px. */
export function fitCanvas(cv: HTMLCanvasElement, maxDpr = 2) {
  const W = cv.clientWidth;
  const H = cv.clientHeight;
  const dpr = Math.min(maxDpr, window.devicePixelRatio || 1);
  const bw = Math.round(W * dpr);
  const bh = Math.round(H * dpr);
  if (cv.width !== bw || cv.height !== bh) {
    cv.width = bw;
    cv.height = bh;
  }
  const ctx = cv.getContext('2d')!;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  return [ctx, W, H] as const;
}
