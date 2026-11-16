import { useEffect, useState } from 'preact/hooks';
import { initPlayer, togglePlay, tune, tuneBy, setVolume } from '../lib/player';
import { startMeta } from '../lib/meta';
import { initPwa } from '../lib/pwa';
import { settings } from '../lib/settings';
import { useMedia } from '../lib/hooks';
import { STATIONS } from '../lib/stations';
import { MobileApp, type Screen } from './mobile/MobileApp';
import { DesktopApp } from './desktop/DesktopApp';
import { Overlays } from './shared/Bits';

initPlayer();
startMeta();
initPwa();

const DESKTOP = '(min-width: 960px) and (min-height: 560px)';

export default function App() {
  const desktop = useMedia(DESKTOP);
  const [screen, setScreen] = useState<Screen>(() => {
    const p = new URLSearchParams(location.search).get('screen');
    return p === 'shelf' || p === 'fx' ? p : 'now';
  });
  const [fxOpen, setFxOpen] = useState(false);

  useEffect(() => {
    let lastVol = settings.peek().volume || 0.85;
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      // Holding a key would toggle play or restart the stream over and over.
      if (e.repeat) return;
      const el = e.target instanceof Element ? e.target : document.body;
      if (el.closest('input, textarea, select, [contenteditable]')) return;
      // Case-insensitive, so Shift/Caps Lock still work (the README documents K, M, F).
      const k = e.key.length === 1 ? e.key.toLowerCase() : e.key;
      if (k === ' ' || k === 'k') {
        if (el.closest('button') && k === ' ') return; // let focused buttons handle space
        e.preventDefault();
        togglePlay();
      } else if (k === 'ArrowRight' || k === 'ArrowDown' || k === 'n') {
        e.preventDefault();
        tuneBy(1);
      } else if (k === 'ArrowLeft' || k === 'ArrowUp' || k === 'p') {
        e.preventDefault();
        tuneBy(-1);
      } else if (/^[1-9]$/.test(k) && Number(k) <= STATIONS.length) {
        tune(Number(k) - 1);
      } else if (k === 'm') {
        const v = settings.peek().volume;
        if (v > 0) lastVol = v;
        setVolume(v > 0 ? 0 : lastVol);
      } else if (k === 'f') {
        setFxOpen((o) => !o);
        setScreen((s) => (s === 'fx' ? 'now' : 'fx'));
      } else if (k === 'Escape') {
        setFxOpen(false);
        setScreen('now');
      }
    };
    addEventListener('keydown', onKey);
    return () => removeEventListener('keydown', onKey);
  }, []);

  return (
    <>
      {desktop ? (
        <DesktopApp fxOpen={fxOpen} setFxOpen={setFxOpen} />
      ) : (
        <MobileApp screen={screen} setScreen={setScreen} />
      )}
      <Overlays />
    </>
  );
}
