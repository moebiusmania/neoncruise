import { useEffect, useRef } from 'preact/hooks';
import { wantPlay } from '../../lib/player';
import { fitCanvas, subscribe, vis } from '../../lib/ticker';
import s from './Spectrum.module.css';

/**
 * Live spectrum strip. Uses the real analyser data when audio-reactive mode is on,
 * otherwise a gentle simulated meter driven by the beat clock.
 */
export function Spectrum({ bars = 48, class: cls }: { bars?: number; class?: string }) {
  const ref = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const cv = ref.current!;
    const heights = new Float32Array(bars);
    const seeds = Float32Array.from({ length: bars }, () => Math.random() * 10);

    return subscribe((t) => {
      const [ctx, W, H] = fitCanvas(cv);
      if (!W || !H) return;
      ctx.clearRect(0, 0, W, H);
      const playing = wantPlay.peek();
      const gap = 2;
      const bw = (W - gap * (bars - 1)) / bars;
      const n = vis.bins.length;

      for (let i = 0; i < bars; i++) {
        let v: number;
        if (vis.live && n) {
          // Log-ish mapping so the low end isn't crammed into two bars.
          const f0 = Math.floor(Math.pow(i / bars, 1.7) * n * 0.7);
          const f1 = Math.max(f0 + 1, Math.floor(Math.pow((i + 1) / bars, 1.7) * n * 0.7));
          let sum = 0;
          for (let k = f0; k < f1; k++) sum += vis.bins[k];
          v = sum / (f1 - f0) / 255;
        } else if (playing) {
          const env = 1 - i / bars;
          v = (0.25 + 0.35 * Math.abs(Math.sin(t * 2.3 + seeds[i]))) * (0.4 + 0.6 * env) * (0.6 + 0.4 * vis.beat);
        } else {
          v = 0;
        }
        heights[i] += (v - heights[i]) * (v > heights[i] ? 0.6 : 0.15);
      }

      const h = vis.hue.toFixed(1);
      ctx.shadowColor = `oklch(0.74 0.19 ${h})`;
      ctx.shadowBlur = 8;
      for (let i = 0; i < bars; i++) {
        const bh = Math.max(2, heights[i] * H);
        const a = 0.45 + heights[i] * 0.55;
        ctx.fillStyle = `oklch(${(0.7 + heights[i] * 0.2).toFixed(3)} 0.19 ${h} / ${a.toFixed(2)})`;
        ctx.fillRect(i * (bw + gap), H - bh, bw, bh);
      }
    });
  }, [bars]);

  return <canvas ref={ref} class={[s.canvas, cls].filter(Boolean).join(' ')} aria-hidden="true" />;
}
