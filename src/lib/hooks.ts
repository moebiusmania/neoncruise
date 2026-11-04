import { useEffect, useRef, useState } from 'preact/hooks';

export function useMedia(query: string) {
  const [match, setMatch] = useState(() => matchMedia(query).matches);
  useEffect(() => {
    const mq = matchMedia(query);
    const on = () => setMatch(mq.matches);
    on();
    mq.addEventListener('change', on);
    return () => mq.removeEventListener('change', on);
  }, [query]);
  return match;
}

/**
 * Keeps a hue "unwrapped" so the CSS --hue transition always takes the short way round
 * (e.g. 350 → 385 instead of 350 → 25).
 */
export function useUnwrappedHue(target: number) {
  const prev = useRef(target);
  const d = ((target - prev.current + 540) % 360) - 180;
  const next = prev.current + d;
  prev.current = next;
  return next;
}
