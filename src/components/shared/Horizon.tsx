import { useEffect, useRef } from 'preact/hooks';
import { wantPlay } from '../../lib/player';
import { approachHue, fitCanvas, motionScale, subscribe, vis } from '../../lib/ticker';
import s from './Horizon.module.css';

interface Props {
  /** Target hue of the scene. */
  hue: number;
  /** Horizon position as a fraction of the height. */
  horizon: number;
  /** Sun radius in CSS px. */
  sun: number;
}

type Star = { x: number; y: number; r: number; p: number; sp: number };

const C = (L: number, c: number, h: number, a: number | string = 1) =>
  `oklch(${L} ${c} ${(((h % 360) + 360) % 360).toFixed(1)} / ${a})`;

function ridge(n: number, lo: number): [number, number][] {
  return Array.from({ length: n + 1 }, (_, k) => {
    const x = k / n;
    const e = Math.pow(Math.abs(x - 0.5) * 2, 1.5);
    return [x, (k % 2 ? 0.55 + 0.45 * Math.random() : lo + 0.3 * Math.random()) * (0.1 + 0.9 * e)];
  });
}

/** Live outrun scene: sky, stars, striped sun, mountains and a scrolling neon grid. */
export function Horizon({ hue, horizon, sun }: Props) {
  const ref = useRef<HTMLCanvasElement>(null);
  const target = useRef({ hue, horizon, sun });
  target.current = { hue, horizon, sun };

  useEffect(() => {
    const cv = ref.current!;
    const sunC = document.createElement('canvas');
    const far = ridge(44, 0.25);
    const near = ridge(26, 0.1);
    let stars: Star[] = [];
    let starArea = 0;
    let hy = target.current.horizon;
    let R = target.current.sun;
    let spd = 0.5;
    let phase = 0;
    vis.hue = target.current.hue;

    const draw = (t: number) => {
      const [ctx, W, H] = fitCanvas(cv);
      if (!W || !H) return;
      const tg = target.current;
      if (W * H !== starArea) {
        starArea = W * H;
        stars = Array.from({ length: Math.round(Math.min(420, starArea / 2700)) }, () => ({
          x: Math.random(),
          y: Math.random(),
          r: Math.random() < 0.15 ? 2 : 1,
          p: Math.random() * 6,
          sp: 0.5 + Math.random() * 2,
        }));
      }

      vis.hue = approachHue(vis.hue, tg.hue, 0.07);
      hy += (tg.horizon - hy) * 0.06;
      R += (tg.sun - R) * 0.06;
      spd += ((wantPlay.peek() ? 1 : 0.12) - spd) * 0.04;
      phase += vis.dt * spd * 1.3 * motionScale;

      const beat = vis.beat * motionScale;
      const h = vis.hue;
      const Y = H * hy;

      // sky
      let g = ctx.createLinearGradient(0, 0, 0, Y);
      g.addColorStop(0, '#04020a');
      g.addColorStop(0.55, C(0.17, 0.09, h + 30));
      g.addColorStop(1, C(0.45, 0.2, h + 10));
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, W, Y);

      const cy = Y - R * 0.62;
      const rg = ctx.createRadialGradient(W / 2, cy, R * 0.6, W / 2, cy, R * 2.8);
      rg.addColorStop(0, C(0.62, 0.24, h, 0.5 + vis.level * 0.25));
      rg.addColorStop(1, C(0.62, 0.24, h, 0));
      ctx.fillStyle = rg;
      ctx.fillRect(0, 0, W, Y);

      for (const st of stars) {
        const y = st.y * Y * 0.85;
        const a = (0.25 + 0.75 * Math.abs(Math.sin(t * st.sp + st.p))) * (1 - y / Y);
        ctx.fillStyle = `rgba(255,240,255,${a.toFixed(3)})`;
        ctx.fillRect(st.x * W, y, st.r, st.r);
      }

      // sun with scrolling cut-out stripes
      const S = Math.ceil(R * 2 + 8);
      if (sunC.width !== S * 2) sunC.width = sunC.height = S * 2;
      const sx = sunC.getContext('2d')!;
      sx.setTransform(2, 0, 0, 2, 0, 0);
      sx.globalCompositeOperation = 'source-over';
      sx.clearRect(0, 0, S, S);
      const gg = sx.createLinearGradient(0, S / 2 - R, 0, S / 2 + R);
      gg.addColorStop(0, C(0.94, 0.12, h + 75));
      gg.addColorStop(0.5, C(0.8, 0.19, h + 35));
      gg.addColorStop(1, C(0.62, 0.26, h));
      sx.fillStyle = gg;
      sx.beginPath();
      sx.arc(S / 2, S / 2, R, 0, Math.PI * 2);
      sx.fill();
      sx.globalCompositeOperation = 'destination-out';
      sx.fillStyle = '#000';
      const stp = R * 0.13;
      const off = (t * 8 * motionScale) % stp;
      for (let k = -1; k < 9; k++) {
        const y = S / 2 + R * 0.02 + k * stp + off;
        const dy = y - S / 2;
        if (dy < 0) continue;
        sx.fillRect(0, y, S, 1 + (dy / R) * R * 0.075);
      }
      sx.globalCompositeOperation = 'source-over';
      ctx.save();
      ctx.beginPath();
      ctx.rect(0, 0, W, Y);
      ctx.clip();
      ctx.shadowColor = C(0.72, 0.26, h);
      ctx.shadowBlur = 36 + beat * 30;
      ctx.drawImage(sunC, W / 2 - S / 2, cy - S / 2, S, S);
      ctx.restore();

      // mountains
      const mtn = (pts: [number, number][], hm: number, fill: string, stroke: string, lw: number) => {
        ctx.beginPath();
        ctx.moveTo(0, Y);
        for (const p of pts) ctx.lineTo(p[0] * W, Y - p[1] * hm);
        ctx.lineTo(W, Y);
        ctx.closePath();
        ctx.fillStyle = fill;
        ctx.fill();
        ctx.strokeStyle = stroke;
        ctx.lineWidth = lw;
        ctx.stroke();
      };
      const mh = Math.max(R, Math.min(W, 900) * 0.25);
      mtn(far, mh * 0.62, C(0.2, 0.1, h + 40), C(0.66, 0.2, h + 20, 0.6), 1);
      mtn(near, mh * 0.42, '#07030d', C(0.76, 0.22, h, 0.9), 1.2);

      // floor + grid
      g = ctx.createLinearGradient(0, Y, 0, H);
      g.addColorStop(0, C(0.22, 0.13, h));
      g.addColorStop(1, '#04020a');
      ctx.fillStyle = g;
      ctx.fillRect(0, Y, W, H - Y);
      ctx.save();
      ctx.beginPath();
      ctx.rect(0, Y, W, H - Y);
      ctx.clip();
      const ph = phase % 1;
      for (let k = 0; k < 44; k++) {
        const y = Y + ((H - Y) * 1.2) / (k + 1 - ph);
        if (y > H + 2) continue;
        if (y - Y < 0.6) break;
        const a = Math.min(1, ((y - Y) / (H - Y)) * 2.2);
        ctx.strokeStyle = C(0.76, 0.22, h, (a * (0.7 + 0.3 * beat)).toFixed(3));
        ctx.lineWidth = 0.6 + a * 1.1 + beat * a * 0.9;
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(W, y);
        ctx.stroke();
      }
      const lg = ctx.createLinearGradient(0, Y, 0, H);
      lg.addColorStop(0, C(0.76, 0.22, h, 0));
      lg.addColorStop(0.35, C(0.76, 0.22, h, 0.5));
      lg.addColorStop(1, C(0.76, 0.22, h, 0.95));
      ctx.strokeStyle = lg;
      ctx.lineWidth = 1.2;
      const N = Math.ceil(W / 2 / 62) + 4;
      for (let j = -N; j <= N; j++) {
        ctx.beginPath();
        ctx.moveTo(W / 2 + j * 1.5, Y);
        ctx.lineTo(W / 2 + j * 62, H);
        ctx.stroke();
      }
      ctx.restore();

      ctx.save();
      ctx.shadowColor = C(0.8, 0.22, h);
      ctx.shadowBlur = 14;
      ctx.fillStyle = C(0.9, 0.15, h + 40);
      ctx.fillRect(0, Y - 1, W, 1.5);
      ctx.restore();
    };

    return subscribe(draw);
  }, []);

  return <canvas ref={ref} class={s.canvas} aria-hidden="true" />;
}
