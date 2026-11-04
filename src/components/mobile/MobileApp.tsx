import { useEffect, useRef, useState } from 'preact/hooks';
import { STATIONS, TOTAL, tapeCode, tapeNum } from '../../lib/stations';
import { insert, station, stationIdx, wantPlay } from '../../lib/player';
import { tracks } from '../../lib/meta';
import { useUnwrappedHue } from '../../lib/hooks';
import { Horizon } from '../shared/Horizon';
import { Cassette } from '../shared/Cassette';
import { Spectrum } from '../shared/Spectrum';
import { PlayButton, RoundButton, StatusPill, useNowTrack } from '../shared/Bits';
import { AudioSettings, Card, FxToggles, MiniPlayer, SleepTimer } from '../shared/Panels';
import { ChevronLeft, ChevronRight, FxIcon, ShelfIcon } from '../shared/Icons';
import s from './MobileApp.module.css';

export type Screen = 'now' | 'shelf' | 'fx';

const SCENE: Record<Screen, { horizon: number; sun: number }> = {
  now: { horizon: 0.5, sun: 100 },
  shelf: { horizon: 0.64, sun: 120 },
  fx: { horizon: 0.3, sun: 80 },
};

export function MobileApp({ screen, setScreen }: { screen: Screen; setScreen: (s: Screen) => void }) {
  const [sel, setSel] = useState(stationIdx.value);
  const viewHue = screen === 'shelf' ? STATIONS[sel].hue : station.value.hue;
  const hue = useUnwrappedHue(viewHue);
  const scale = Math.min(1.25, Math.min(innerWidth, innerHeight * 0.55) / 402);
  const scene = SCENE[screen];

  const openShelf = () => {
    setSel(stationIdx.value);
    setScreen('shelf');
  };

  return (
    <div class={`theme ${s.app}`} style={{ '--hue': hue }}>
      <Horizon hue={viewHue} horizon={scene.horizon} sun={scene.sun * scale} />
      {screen === 'now' && <NowScreen onShelf={openShelf} onFx={() => setScreen('fx')} />}
      {screen === 'shelf' && <ShelfScreen sel={sel} setSel={setSel} onBack={() => setScreen('now')} />}
      {screen === 'fx' && <FxScreen onBack={() => setScreen('now')} />}
    </div>
  );
}

function NowScreen({ onShelf, onFx }: { onShelf: () => void; onFx: () => void }) {
  const i = stationIdx.value;
  const st = station.value;
  const t = useNowTrack();
  return (
    <main class={s.screen} key="now">
      <header class={s.top}>
        <h1 class={s.logo}>
          <span class={s.appName}>NEON CRUISE</span>
          <span>
            NIGHTRIDE<span class={s.fm}> FM</span>
          </span>
        </h1>
        <StatusPill />
      </header>

      <div class={s.stationBlock}>
        <div class={s.tapeNo}>
          TAPE {tapeNum(i)} / {TOTAL} · SIDE A
        </div>
        <div class={s.stationName} key={st.id}>
          {st.name}
        </div>
        <div class={s.stationTag}>{st.tag}</div>
      </div>

      <div class={s.spacer} />

      <button class={s.deck} onClick={onShelf} aria-label="Open tape shelf">
        <div class={s.deckTilt}>
          <Cassette
            key={st.id}
            class={s.deckTape}
            hue={st.hue}
            name={st.name}
            code={tapeCode(i)}
            progress={t.progress}
            spinning={wantPlay.value}
          />
        </div>
      </button>

      <div class={s.track}>
        <div class={s.trackTitle}>{t.title}</div>
        <div class={s.trackArtist}>{t.artist}</div>
        <div class={s.timeline}>
          <span>{t.pos}</span>
          <Spectrum bars={36} class={s.spectrum} />
          <span class={s.live}>LIVE</span>
        </div>
      </div>

      <nav class={s.transport}>
        <button class={s.side} onClick={onShelf}>
          <ShelfIcon class={s.sideIco} />
          <span>SHELF</span>
        </button>
        <RoundButton dir="prev" />
        <PlayButton />
        <RoundButton dir="next" />
        <button class={s.side} onClick={onFx}>
          <FxIcon class={s.sideIco} />
          <span>FX</span>
        </button>
      </nav>
    </main>
  );
}

function ShelfScreen({ sel, setSel, onBack }: { sel: number; setSel: (i: number) => void; onBack: () => void }) {
  const [inserting, setInserting] = useState(false);
  const sx = useRef<number | null>(null);
  const swiped = useRef(0);
  const timer = useRef(0);
  const selSt = STATIONS[sel];
  const selTrack = tracks.value[selSt.id];
  const inDeck = sel === stationIdx.value && wantPlay.value;
  const clamp = (i: number) => Math.max(0, Math.min(STATIONS.length - 1, i));

  useEffect(() => () => clearTimeout(timer.current), []);

  const doInsert = () => {
    if (inserting) return;
    insert(sel); // start audio inside the user gesture (required on iOS)
    setInserting(true);
    timer.current = window.setTimeout(onBack, 650);
  };

  const onKey = (e: KeyboardEvent) => {
    if (e.key === 'ArrowLeft') setSel(clamp(sel - 1));
    else if (e.key === 'ArrowRight') setSel(clamp(sel + 1));
    else return;
    e.preventDefault();
    e.stopPropagation();
  };

  return (
    <main class={s.screen} key="shelf" onKeyDown={onKey}>
      <header class={s.bar}>
        <button class={s.back} onClick={onBack}>
          <ChevronLeft class={s.backIco} /> DECK
        </button>
        <h1 class={s.barTitle}>TAPE SHELF</h1>
        <div class={s.barRight}>
          {tapeNum(sel)}/{TOTAL}
        </div>
      </header>

      <div class={s.slotWrap}>
        <div class={s.slot} />
        <div class={s.slotHint}>DECK SLOT · TAP CENTER TAPE TO INSERT</div>
      </div>

      <div
        class={s.flow}
        onPointerDown={(e) => (sx.current = e.clientX)}
        onPointerUp={(e) => {
          if (sx.current == null) return;
          const dx = e.clientX - sx.current;
          sx.current = null;
          if (Math.abs(dx) > 40) {
            swiped.current = Date.now();
            setSel(clamp(sel + (dx < 0 ? 1 : -1)));
          }
        }}
        onPointerCancel={() => (sx.current = null)}
      >
        {STATIONS.map((x, i) => {
          const d = i - sel;
          const center = d === 0;
          return (
            <button
              key={x.id}
              class={s.flowItem}
              data-d={Math.max(-3, Math.min(3, d))}
              data-inserting={(inserting && center) || undefined}
              style={{ '--d': d, zIndex: 10 - Math.abs(d) }}
              tabIndex={center ? 0 : -1}
              aria-label={center ? `Insert ${x.name}` : `Select ${x.name}`}
              onClick={() => {
                if (Date.now() - swiped.current < 300) return;
                center ? doInsert() : setSel(i);
              }}
            >
              <Cassette hue={x.hue} name={x.name} code={tapeCode(i)} detailed={Math.abs(d) < 2} class={s.flowTape} />
            </button>
          );
        })}
      </div>

      <div class={s.selInfo}>
        <div class={s.selName} key={selSt.id}>
          {selSt.name}
        </div>
        <div class={s.stationTag}>{selSt.tag}</div>
        <div class={s.onAir}>
          ON AIR · {selTrack ? `${selTrack.artist} — ${selTrack.title}` : 'tuning…'}
        </div>
        <div class={s.dots}>
          {STATIONS.map((x, i) => (
            <button
              key={x.id}
              class={s.dotBtn}
              data-on={i === sel || undefined}
              style={{ '--h': x.hue }}
              onClick={() => setSel(i)}
              aria-label={x.name}
            />
          ))}
        </div>
      </div>

      <div class={s.shelfActions}>
        <button class={s.square} onClick={() => setSel(clamp(sel - 1))} aria-label="Previous tape">
          <ChevronLeft class={s.squareIco} />
        </button>
        <button class={s.insert} onClick={doInsert}>
          {inserting ? 'LOADING…' : inDeck ? 'IN DECK · REPLAY' : 'INSERT TAPE'}
        </button>
        <button class={s.square} onClick={() => setSel(clamp(sel + 1))} aria-label="Next tape">
          <ChevronRight class={s.squareIco} />
        </button>
      </div>
    </main>
  );
}

function FxScreen({ onBack }: { onBack: () => void }) {
  return (
    <main class={s.screen} key="fx">
      <header class={s.bar}>
        <button class={s.back} onClick={onBack}>
          <ChevronLeft class={s.backIco} /> DECK
        </button>
        <h1 class={s.barTitle}>SIGNAL FX</h1>
        <div class={s.barRight} />
      </header>
      <div class={s.scroll}>
        <Card>
          <FxToggles />
        </Card>
        <Card title="SLEEP TIMER">
          <SleepTimer />
        </Card>
        <Card title="AUDIO">
          <AudioSettings />
        </Card>
      </div>
      <MiniPlayer class={s.mini} />
    </main>
  );
}
