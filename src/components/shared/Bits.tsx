import { useComputed } from '@preact/signals';
import { history, listeners, tracks } from '../../lib/meta';
import { fmt, now, status, statusLabel, station, togglePlay, tuneBy, wantPlay } from '../../lib/player';
import { NextIcon, PauseIcon, PlayIcon, PrevIcon } from './Icons';
import s from './Bits.module.css';

/** Current track for the active station, with elapsed time since it started. */
export function useNowTrack(id?: string) {
  return useComputed(() => {
    const sid = id ?? station.value.id;
    const t = tracks.value[sid];
    const elapsed = t?.at ? (now.value - t.at) / 1000 : null;
    return {
      title: t?.title || 'Tuning in…',
      artist: t?.artist || 'Waiting for the signal',
      known: !!t,
      elapsed,
      pos: elapsed != null ? fmt(elapsed) : '--:--',
      /** Tape wind progress for the reels: a loose estimate (live radio has no duration). */
      progress: elapsed != null ? Math.min(1, elapsed / 300) : 0.5,
    };
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

/** CRT effects stacked over the whole app. */
export function Overlays({ scan, flicker, noise, burst }: { scan: boolean; flicker: boolean; noise: boolean; burst: boolean }) {
  return (
    <>
      {scan && <div class={s.scan} />}
      {flicker && <div class={s.flicker} />}
      <div class={s.noise} data-on={noise || undefined} data-burst={burst || undefined} />
      <div class={s.vignette} />
    </>
  );
}
