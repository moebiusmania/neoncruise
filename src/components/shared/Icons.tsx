import type { SVGAttributes } from 'preact';

type P = SVGAttributes<SVGSVGElement>;

const base = { 'aria-hidden': true, focusable: 'false' } as const;

export const PlayIcon = (p: P) => (
  <svg viewBox="0 0 24 28" {...base} {...p}>
    <path d="M0 0 24 14 0 28Z" fill="currentColor" />
  </svg>
);

export const PauseIcon = (p: P) => (
  <svg viewBox="0 0 20 26" {...base} {...p}>
    <rect x="0" width="7" height="26" fill="currentColor" />
    <rect x="13" width="7" height="26" fill="currentColor" />
  </svg>
);

export const PrevIcon = (p: P) => (
  <svg viewBox="0 0 18 12" {...base} {...p}>
    <path d="M9 0 0 6l9 6ZM18 0 9 6l9 6Z" fill="currentColor" />
  </svg>
);

export const NextIcon = (p: P) => (
  <svg viewBox="0 0 18 12" {...base} {...p}>
    <path d="m0 0 9 6-9 6ZM9 0l9 6-9 6Z" fill="currentColor" />
  </svg>
);

/** Three tape spines. */
export const ShelfIcon = (p: P) => (
  <svg viewBox="0 0 21 16" {...base} {...p}>
    <rect x="0" width="5" height="16" fill="#fff" />
    <rect x="8" width="5" height="16" fill="var(--acc)" />
    <rect x="16" width="5" height="16" fill="#fff" />
  </svg>
);

/** Three slider lines. */
export const FxIcon = (p: P) => (
  <svg viewBox="0 0 18 15" {...base} {...p}>
    <rect y="0" width="18" height="3" fill="#fff" />
    <rect y="6" width="18" height="3" fill="var(--acc)" />
    <rect y="12" width="18" height="3" fill="#fff" />
  </svg>
);

export const SpeakerIcon = ({ level = 1, ...p }: P & { level?: number }) => (
  <svg viewBox="0 0 24 24" {...base} {...p}>
    <path d="M3 9h4l5-4v14l-5-4H3Z" fill="currentColor" />
    {level > 0 && <path d="M15.5 9.2a4 4 0 0 1 0 5.6" stroke="currentColor" stroke-width="2" fill="none" />}
    {level > 0.5 && <path d="M18.3 6.4a8 8 0 0 1 0 11.2" stroke="currentColor" stroke-width="2" fill="none" />}
    {level === 0 && <path d="m16 9 6 6m0-6-6 6" stroke="currentColor" stroke-width="2" />}
  </svg>
);

export const ChevronLeft = (p: P) => (
  <svg viewBox="0 0 10 16" {...base} {...p}>
    <path d="M8 1 2 8l6 7" stroke="currentColor" stroke-width="2.4" fill="none" stroke-linecap="square" />
  </svg>
);

export const ChevronRight = (p: P) => (
  <svg viewBox="0 0 10 16" {...base} {...p}>
    <path d="m2 1 6 7-6 7" stroke="currentColor" stroke-width="2.4" fill="none" stroke-linecap="square" />
  </svg>
);

export const InstallIcon = (p: P) => (
  <svg viewBox="0 0 24 24" {...base} {...p}>
    <path d="M12 3v11m0 0-4.5-4.5M12 14l4.5-4.5M4 16v4h16v-4" stroke="currentColor" stroke-width="2" fill="none" />
  </svg>
);

/** Cassette reel: hub, six spokes and a ring, with the tape pack wound around it. */
export const Reel = ({ pack, spinning, class: cls }: { pack: number; spinning: boolean; class?: string }) => (
  <svg viewBox="-26 -26 52 52" class={cls} aria-hidden="true" data-spin={spinning || undefined}>
    <circle r={15 + pack} fill="#2b1b18" />
    <circle r={15} fill="#0b0610" />
    <g class="spokes">
      {[0, 60, 120, 180, 240, 300].map((a) => (
        <path key={a} d="M-0.8 -7 L0.8 -7 L1.6 -15 L-1.6 -15 Z" fill="#efe7f3" transform={`rotate(${a})`} />
      ))}
      <circle r={12.5} fill="none" stroke="#efe7f3" stroke-width="1" />
      <circle r={5.5} fill="none" stroke="#efe7f3" stroke-width="3" />
      <circle r={4} fill="#0b0610" />
    </g>
  </svg>
);
