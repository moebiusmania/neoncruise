import type { ComponentChildren } from 'preact';
import { settings, setSetting, toggleSetting } from '../../lib/settings';
import { fmt, now, setSleep, setVolume, sleepEnd, sleepMin, station, volumeControllable } from '../../lib/player';
import { SpeakerIcon } from './Icons';
import { PlayButton, useNowTrack } from './Bits';
import s from './Panels.module.css';

export function Card({ title, children, class: cls }: { title?: string; children: ComponentChildren; class?: string }) {
  return (
    <section class={[s.card, cls].filter(Boolean).join(' ')}>
      {title && <h2 class={s.cardTitle}>{title}</h2>}
      {children}
    </section>
  );
}

function ToggleRow({ label, desc, on, onToggle }: { label: string; desc: string; on: boolean; onToggle: () => void }) {
  return (
    <button class={s.row} role="switch" aria-checked={on} onClick={onToggle}>
      <span class={s.rowText}>
        <span class={s.rowLabel}>{label}</span>
        <span class={s.rowDesc}>{desc}</span>
      </span>
      <span class={s.switch} data-on={on || undefined}>
        <i />
      </span>
    </button>
  );
}

const FX_ROWS = [
  ['scan', 'SCANLINES', 'CRT raster across the app'],
  ['flicker', 'FLICKER', 'Unstable tube brightness'],
  ['noise', 'NOISE', 'Analog grain on screen'],
] as const;

export function FxToggles() {
  const st = settings.value;
  return (
    <div class={s.rows}>
      {FX_ROWS.map(([k, label, desc]) => (
        <ToggleRow key={k} label={label} desc={desc} on={st[k]} onToggle={() => toggleSetting(k)} />
      ))}
    </div>
  );
}

const SLEEP_OPTS = [0, 15, 30, 60, 90];

export function SleepTimer() {
  const end = sleepEnd.value;
  const left = end ? Math.max(0, Math.round((end - now.value) / 1000)) : 0;
  const at = end ? new Date(end) : null;
  return (
    <div class={s.sleep}>
      <div class={s.digitsRow}>
        <span class={s.digits}>{String(end ? Math.ceil(left / 60) : 0).padStart(3, '0')}</span>
        <span class={s.unit}>MIN</span>
      </div>
      <p class={s.note}>
        {at
          ? `Tape fades out at ${String(at.getHours()).padStart(2, '0')}:${String(at.getMinutes()).padStart(2, '0')} · ${fmt(left)} left`
          : 'Plays until you stop it'}
      </p>
      <div class={s.seg} role="radiogroup" aria-label="Sleep timer">
        {SLEEP_OPTS.map((m) => (
          <button
            key={m}
            role="radio"
            aria-checked={sleepMin.value === m}
            data-on={sleepMin.value === m || undefined}
            onClick={() => setSleep(m)}
          >
            {m ? m : 'OFF'}
          </button>
        ))}
      </div>
    </div>
  );
}

export function AudioSettings() {
  const st = settings.value;
  const vol = st.volume;
  return (
    <div class={s.rows}>
      {volumeControllable.value && (
        <div class={s.volume}>
          <button
            class={s.mute}
            onClick={() => setVolume(vol > 0 ? 0 : 0.85)}
            aria-label={vol > 0 ? 'Mute' : 'Unmute'}
          >
            <SpeakerIcon level={vol === 0 ? 0 : vol} />
          </button>
          <input
            class={s.slider}
            type="range"
            min={0}
            max={1}
            step={0.01}
            value={vol}
            style={{ '--v': vol }}
            aria-label="Volume"
            onInput={(e) => setVolume(Number((e.target as HTMLInputElement).value))}
          />
          <span class={s.volNum}>{String(Math.round(vol * 100)).padStart(3, '0')}</span>
        </div>
      )}
      <ToggleRow
        label="REACTIVE"
        desc="Grid and spectrum follow the real audio"
        on={st.reactive}
        onToggle={() => toggleSetting('reactive')}
      />
      <ToggleRow
        label="TAPE HISS"
        desc={st.reactive ? 'Mix faint analog hiss into the stream' : 'Needs REACTIVE on'}
        on={st.hiss && st.reactive}
        onToggle={() => (st.reactive ? toggleSetting('hiss') : (setSetting('reactive', true), setSetting('hiss', true)))}
      />
    </div>
  );
}

export function MiniPlayer({ class: cls }: { class?: string }) {
  const st = station.value;
  const t = useNowTrack();
  return (
    <div class={[s.mini, cls].filter(Boolean).join(' ')}>
      <div class={s.miniTape} style={{ '--h': st.hue }}>
        <i />
        <i />
      </div>
      <div class={s.miniText}>
        <div class={s.miniTitle}>{t.title}</div>
        <div class={s.miniSub}>
          {st.name} FM · {t.artist}
        </div>
      </div>
      <PlayButton size="sm" />
    </div>
  );
}
