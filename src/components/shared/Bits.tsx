import { useComputed } from '@preact/signals';
import { useEffect, useState } from 'preact/hooks';
import { history, listeners, tracks } from '../../lib/meta';
import { burstAt, fmt, now, status, statusLabel, station, togglePlay, tuneBy, wantPlay } from '../../lib/player';
import { settings } from '../../lib/settings';
import { NextIcon, PauseIcon, PlayIcon, PrevIcon } from './Icons';
import s from './Bits.module.css';

/**
 * Current track for the active station. Deliberately doesn't read the 1 Hz `now` clock, so the
 * screens using it don't re-render every second; see `TrackClock` and `useTapeProgress`.
 */
export function useNowTrack(id?: string) {
  return useComputed(() => {
    const t = tracks.value[id ?? station.value.id];
    return {
      title: t?.title || 'Tuning in…',
      artist: t?.artist || 'Waiting for the signal',
      known: !!t,
    };
  }).value;
}

const elapsedSecs = (id?: string) => {
  const at = tracks.value[id ?? station.value.id]?.at;
  return at ? (now.value - at) / 1000 : null;
};

/** Elapsed time since the track started. Only this span re-renders on each clock tick. */
export function TrackClock({ id }: { id?: string }) {
  const pos = useComputed(() => {
    const e = elapsedSecs(id);
    return e != null ? fmt(e) : '--:--';
  }).value;
  return <span>{pos}</span>;
}

const PROGRESS_STEPS = 40;

/**
 * Tape wind progress for the reels: a loose estimate (live radio has no duration).
 * Quantised so the cassette only re-renders when the tape pack visibly changes (~every 7 s).
 */
export function useTapeProgress(id?: string) {
  return useComputed(() => {
    const e = elapsedSecs(id);
    return e != null ? Math.round(Math.min(1, e / 300) * PROGRESS_STEPS) / PROGRESS_STEPS : 0.5;
  }).value;
}

export function useListeners(id?: string) {
  return useComputed(() => listeners.value[id ?? station.value.id]).value;
}

export function useHistory(id?: string) {
  return useComputed(() => history.value[id ?? station.value.id] ?? []).value;
}

export function StatusPill({ class: cls }: { class?: string }) {
  const st = status.value;
  return (
    <div class={[s.pill, cls].filter(Boolean).join(' ')} data-status={st} role="status" aria-live="polite">
      <i class={s.dot} />
      <span>{statusLabel.value}</span>
    </div>
  );
}

export function PlayButton({ size = 'lg', class: cls }: { size?: 'lg' | 'sm'; class?: string }) {
  const playing = wantPlay.value;
  const loading = status.value === 'loading';
  return (
    <button
      class={[s.play, cls].filter(Boolean).join(' ')}
      data-size={size}
      data-loading={loading || undefined}
      onClick={togglePlay}
      aria-label={playing ? 'Pause' : 'Play'}
      aria-pressed={playing}
    >
      {playing ? <PauseIcon class={s.pauseIco} /> : <PlayIcon class={s.playIco} />}
    </button>
  );
}

export function RoundButton({ dir }: { dir: 'prev' | 'next' }) {
  return (
    <button
      class={s.round}
      onClick={() => tuneBy(dir === 'prev' ? -1 : 1)}
      aria-label={dir === 'prev' ? 'Previous station' : 'Next station'}
    >
      {dir === 'prev' ? <PrevIcon class={s.skipIco} /> : <NextIcon class={s.skipIco} />}
    </button>
  );
}

/**
 * CRT effects stacked over the whole app. Reads its own signals so that settings changes
 * (e.g. dragging the volume slider) and tape changes don't re-render the whole tree from <App>.
 */
export function Overlays() {
  const { scan, flicker, noise } = settings.value;
  const at = burstAt.value;
  const [burst, setBurst] = useState(false);

  // Static burst on every tape change.
  useEffect(() => {
    if (!at) return;
    setBurst(true);
    const t = setTimeout(() => setBurst(false), 320);
    return () => clearTimeout(t);
  }, [at]);

  return (
    <>
      {scan && <div class={s.scan} />}
      {flicker && <div class={s.flicker} />}
      <div class={s.noise} data-on={noise || undefined} data-burst={burst || undefined} />
      <div class={s.vignette} />
    </>
  );
}
