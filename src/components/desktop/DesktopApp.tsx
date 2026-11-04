import { useState } from 'preact/hooks';
import { STATIONS, TOTAL, tapeCode, tapeNum } from '../../lib/stations';
import { insert, sleepEnd, station, stationIdx, status, wantPlay } from '../../lib/player';
import { listeners, metaOnline, tracks } from '../../lib/meta';
import { canInstall, promptInstall } from '../../lib/pwa';
import { useMedia, useUnwrappedHue } from '../../lib/hooks';
import { Horizon } from '../shared/Horizon';
import { Cassette } from '../shared/Cassette';
import { Spectrum } from '../shared/Spectrum';
import { PlayButton, RoundButton, StatusPill, useHistory, useListeners, useNowTrack } from '../shared/Bits';
import { AudioSettings, Card, FxToggles, SleepTimer } from '../shared/Panels';
import { FxIcon, InstallIcon } from '../shared/Icons';
import s from './DesktopApp.module.css';

export function DesktopApp({ fxOpen, setFxOpen }: { fxOpen: boolean; setFxOpen: (v: boolean) => void }) {
  const [hover, setHover] = useState<number | null>(null);
  const st = station.value;
  const viewHue = hover != null ? STATIONS[hover].hue : st.hue;
  const hue = useUnwrappedHue(viewHue);
  const wide = useMedia('(min-width: 1240px)');
  const tall = typeof innerHeight !== 'undefined' ? innerHeight : 900;

  return (
    <div class={`theme ${s.app}`} style={{ '--hue': hue }} data-fx={fxOpen || wide || undefined}>
      <Horizon hue={viewHue} horizon={0.56} sun={Math.min(170, tall * 0.16)} />

      <header class={s.titlebar}>
        <div class={s.logo}>
          <span class={s.appName}>NEON CRUISE</span>
          <i class={s.logoSep} aria-hidden="true" />
          <span>
            NIGHTRIDE<span class={s.fm}> FM</span>
          </span>
        </div>
        <div class={s.titleCenter}>
          <StatusPill />
        </div>
        <div class={s.titleRight}>
          {canInstall.value && (
            <button class={s.chip} onClick={promptInstall}>
              <InstallIcon class={s.chipIco} /> INSTALL
            </button>
          )}
          {!wide && (
            <button class={s.chip} data-on={fxOpen || undefined} onClick={() => setFxOpen(!fxOpen)} aria-expanded={fxOpen}>
              <FxIcon class={s.chipIco} /> FX
            </button>
          )}
        </div>
      </header>

      <Rack onHover={setHover} />
      <Stage />
      <SidePanel />
      <StatusBar />
    </div>
  );
}

function Rack({ onHover }: { onHover: (i: number | null) => void }) {
  const cur = stationIdx.value;
  const playing = wantPlay.value;
  return (
    <aside class={s.rack} aria-label="Tape shelf" onPointerLeave={() => onHover(null)}>
      <div class={s.panelHead}>
        <h2>TAPE SHELF</h2>
        <span>
          {tapeNum(cur)}/{TOTAL}
        </span>
      </div>
      <ol class={s.rackList}>
        {STATIONS.map((x, i) => {
          const t = tracks.value[x.id];
          const n = listeners.value[x.id];
          const active = i === cur;
          return (
            <li key={x.id}>
              <button
                class={s.rackItem}
                data-active={active || undefined}
                data-playing={(active && playing) || undefined}
                style={{ '--h': x.hue }}
                onPointerEnter={() => onHover(i)}
                onFocus={() => onHover(i)}
                onBlur={() => onHover(null)}
                onClick={() => insert(i)}
                aria-current={active || undefined}
              >
                <span class={s.spine}>
                  <span>{tapeCode(i)}</span>
                </span>
                <span class={s.rackText}>
                  <span class={s.rackTop}>
                    <span class={s.rackNum}>{tapeNum(i)}</span>
                    <span class={s.rackName}>{x.name}</span>
                  </span>
                  <span class={s.rackNow}>{t ? `${t.artist} — ${t.title}` : x.tag}</span>
                </span>
                <span class={s.rackMeta}>
                  {active && playing ? (
                    <span class={s.eq} aria-label="Playing">
                      <i />
                      <i />
                      <i />
                      <i />
                    </span>
                  ) : (
                    n != null && <span class={s.listeners}>{n}</span>
                  )}
                </span>
              </button>
            </li>
          );
        })}
      </ol>
      <p class={s.rackHint}>
        Click a tape to slot it in · <kbd>1</kbd>–<kbd>7</kbd>
      </p>
    </aside>
  );
}

function Stage() {
  const i = stationIdx.value;
  const st = station.value;
  const t = useNowTrack();
  const n = useListeners();
  return (
    <main class={s.stage}>
      <div class={s.stageHead}>
        <div class={s.tapeNo}>
          TAPE {tapeNum(i)} / {TOTAL} · SIDE A{n != null && <span class={s.tuned}> · {n} TUNED IN</span>}
        </div>
        <h1 class={s.stationName} key={st.id}>
          {st.name}
        </h1>
        <div class={s.stationTag}>{st.tag}</div>
      </div>

      <div class={s.deck}>
        <div class={s.deckSlot} />
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
      </div>

      <div class={s.console}>
        <div class={s.track}>
          <div class={s.trackTitle} title={t.title}>
            {t.title}
          </div>
          <div class={s.trackArtist}>{t.artist}</div>
        </div>
        <div class={s.timeline}>
          <span>{t.pos}</span>
          <Spectrum bars={64} class={s.spectrum} />
          <span class={s.live}>LIVE</span>
        </div>
        <div class={s.transport}>
          <RoundButton dir="prev" />
          <PlayButton />
          <RoundButton dir="next" />
        </div>
      </div>
    </main>
  );
}

function SidePanel() {
  const log = useHistory();
  const st = station.value;
  return (
    <aside class={s.side} aria-label="Signal FX and settings">
      <div class={s.panelHead}>
        <h2>SIGNAL FX</h2>
      </div>
      <div class={s.sideScroll}>
        <Card>
          <FxToggles />
        </Card>
        <Card title="SLEEP TIMER">
          <SleepTimer />
        </Card>
        <Card title="AUDIO">
          <AudioSettings />
        </Card>
        <Card title={`ON-AIR LOG · ${st.name}`} class={s.logCard}>
          {log.length ? (
            <ol class={s.log}>
              {log.map((x, k) => (
                <li key={`${x.artist}-${x.title}`} data-now={k === 0 || undefined}>
                  <span class={s.logIdx}>{k === 0 ? 'NOW' : String(k).padStart(2, '0')}</span>
                  <span class={s.logText}>
                    <span>{x.title}</span>
                    <small>{x.artist}</small>
                  </span>
                </li>
              ))}
            </ol>
          ) : (
            <p class={s.logEmpty}>Listening for track changes…</p>
          )}
        </Card>
      </div>
    </aside>
  );
}

function StatusBar() {
  const total = Object.values(listeners.value).reduce((a, b) => a + b, 0);
  const st = status.value;
  return (
    <footer class={s.statusbar}>
      <span data-ok={st === 'playing' || undefined}>
        <i /> STREAM {st === 'playing' ? '320 KBPS · MP3' : st.toUpperCase()}
      </span>
      <span data-ok={metaOnline.value || undefined}>
        <i /> META {metaOnline.value ? 'LIVE' : 'OFFLINE'}
      </span>
      {total > 0 && <span>{total} LISTENERS ON THE NETWORK</span>}
      {sleepEnd.value > 0 && <span class={s.sleepFlag}>SLEEP ARMED</span>}
      <span class={s.keys}>
        <kbd>SPACE</kbd> PLAY <kbd>←</kbd>
        <kbd>→</kbd> TUNE <kbd>M</kbd> MUTE
      </span>
    </footer>
  );
}
