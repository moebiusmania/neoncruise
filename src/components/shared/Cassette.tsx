import { Reel } from './Icons';
import s from './Cassette.module.css';

interface Props {
  hue: number;
  name: string;
  code: string;
  /** 0..1 how far the tape has wound from the left reel to the right. */
  progress?: number;
  spinning?: boolean;
  /** Show screws and the head window details (off for distant coverflow tapes). */
  detailed?: boolean;
  class?: string;
}

/**
 * A cassette drawn in CSS that scales with its container width
 * (all measurements are in container-query units).
 */
export function Cassette({ hue, name, code, progress = 0.5, spinning = false, detailed = true, class: cls }: Props) {
  const packL = 2 + (1 - progress) * 8;
  const packR = 2 + progress * 8;
  return (
    <div class={[s.wrap, cls].filter(Boolean).join(' ')} style={{ '--h': hue }}>
      <div class={s.body}>
        {detailed && (
          <>
            <i class={s.screw} data-pos="tl" />
            <i class={s.screw} data-pos="tr" />
            <i class={s.screw} data-pos="bl" />
            <i class={s.screw} data-pos="br" />
          </>
        )}
        <div class={s.label}>
          <div class={s.labelHead}>
            <span class={s.name}>{name}</span>
            <span class={s.code}>{code}</span>
          </div>
          <div class={s.stripes} />
          <div class={s.window}>
            <Reel pack={packL} spinning={spinning} class={s.reel} />
            <Reel pack={packR} spinning={spinning} class={s.reel} />
          </div>
        </div>
        <div class={s.head}>
          {detailed && (
            <>
              <i class={s.hole} />
              <i class={s.slot} />
              <i class={s.slot} />
              <i class={s.hole} />
            </>
          )}
        </div>
      </div>
    </div>
  );
}
