//! Player state and transport logic, mirroring `src/lib/player.ts`.

use crate::audio::{AudioEvent, Engine};
use crate::color::approach_hue;
use crate::meta::{Meta, MetaState, Track};
use crate::settings::Settings;
use crate::stations::{STATIONS, Station, index_of, stream_url, wrap_index};
use crate::sync::LockExt;
use crate::vis::Vis;
use ratatui::layout::Rect;
use std::sync::mpsc::{Receiver, channel};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Status {
    Idle,
    Loading,
    Playing,
    Paused,
    Error,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Screen {
    Now,
    Shelf,
    Fx,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Toggle {
    Scan,
    Flicker,
    Noise,
    Reactive,
    Hiss,
}

/// Something a mouse click can trigger; regions are collected while drawing.
#[derive(Clone, Copy)]
pub enum Action {
    Select(usize),
    TogglePlay,
    Prev,
    Next,
    Toggle(Toggle),
    Sleep(u32),
    Volume,
    Mute,
    Screen(Screen),
    Fx,
}

pub const SLEEP_OPTS: [u32; 5] = [0, 15, 30, 60, 90];
const FADE_SECS: f32 = 12.0;
/// Coalesce settings writes: volume scrolls/drags change them every frame.
const SAVE_DELAY: Duration = Duration::from_millis(500);

pub struct App {
    pub settings: Settings,
    pub meta: Meta,
    /// Copy of the shared metadata, refreshed only when its version changes, so drawing
    /// doesn't lock the mutex (and clone the history) several times every frame.
    snap: MetaState,
    pub engine: Engine,
    events: Receiver<AudioEvent>,
    pub vis: Vis,

    pub station_idx: usize,
    pub status: Status,
    /// What the user asked for; `status` is what the stream is actually doing.
    pub want_play: bool,
    retries: u32,
    retry_at: Option<Instant>,
    loading_since: Instant,

    pub sleep_end: Option<Instant>,
    pub sleep_min: u32,
    fade: f32,

    /// Last station switch, drives the static burst and the tape insert animation.
    pub burst_at: Option<Instant>,
    pub hover: Option<usize>,
    pub fx_open: bool,
    pub screen: Screen,
    /// Highlighted tape on the narrow-layout shelf.
    pub sel: usize,
    last_vol: f32,
    /// When unsaved settings changes should be written.
    save_at: Option<Instant>,
    /// Write settings to disk (off for headless snapshots).
    pub persist: bool,

    pub desktop: bool,
    pub hits: Vec<(Rect, Action)>,
    pub start: Instant,
    pub quit: bool,
}

pub fn epoch_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

pub fn fmt(secs: f64) -> String {
    let s = secs.max(0.0).floor() as u64;
    let (h, m, s) = (s / 3600, (s % 3600) / 60, s % 60);
    if h > 0 {
        format!("{h}:{m:02}:{s:02}")
    } else {
        format!("{m:02}:{s:02}")
    }
}

/// The current track, borrowed from the metadata snapshot (no per-frame string clones).
pub struct NowTrack<'a> {
    pub title: &'a str,
    pub artist: &'a str,
    /// Seconds since the track started, when the feed says.
    pub elapsed: Option<f64>,
}

impl NowTrack<'_> {
    /// Elapsed time as `mm:ss`, formatted only where it's shown.
    pub fn pos(&self) -> String {
        self.elapsed.map(fmt).unwrap_or_else(|| "--:--".into())
    }

    /// Tape wind progress for the reels: a loose estimate (live radio has no duration).
    pub fn progress(&self) -> f32 {
        self.elapsed
            .map(|e| (e / 300.0).min(1.0) as f32)
            .unwrap_or(0.5)
    }
}

impl App {
    pub fn new(meta: Meta) -> App {
        let settings = Settings::load();
        let (tx, rx) = channel();
        let engine = Engine::new(tx, settings.volume);
        let station_idx = index_of(&settings.station).unwrap_or(0);
        let hue = STATIONS[station_idx].hue;
        App {
            last_vol: if settings.volume > 0.0 {
                settings.volume
            } else {
                0.85
            },
            settings,
            meta,
            snap: MetaState::default(),
            engine,
            events: rx,
            vis: Vis::new(hue),
            station_idx,
            status: Status::Idle,
            want_play: false,
            retries: 0,
            retry_at: None,
            loading_since: Instant::now(),
            sleep_end: None,
            sleep_min: 0,
            fade: 1.0,
            burst_at: None,
            hover: None,
            fx_open: false,
            screen: Screen::Now,
            sel: station_idx,
            save_at: None,
            persist: true,
            desktop: true,
            hits: Vec::new(),
            start: Instant::now(),
            quit: false,
        }
    }

    pub fn station(&self) -> &'static Station {
        &STATIONS[self.station_idx]
    }

    /* -------------------------------------------------------------- transport */

    fn start_stream(&mut self) {
        self.loading_since = Instant::now();
        self.engine.play(stream_url(self.station().id));
    }

    pub fn play(&mut self) {
        self.retry_at = None;
        self.retries = 0;
        self.fade = 1.0;
        self.want_play = true;
        self.status = Status::Loading;
        self.start_stream();
    }

    pub fn pause(&mut self) {
        self.retry_at = None;
        self.want_play = false;
        self.status = Status::Paused;
        self.engine.stop();
    }

    pub fn toggle_play(&mut self) {
        if self.want_play {
            self.pause()
        } else {
            self.play()
        }
    }

    fn set_station(&mut self, i: usize) {
        self.station_idx = i;
        self.sel = i;
        self.settings.station = STATIONS[i].id.into();
        self.mark_dirty();
        self.burst_at = Some(Instant::now());
    }

    pub fn tune(&mut self, i: isize) {
        let next = wrap_index(i);
        if next == self.station_idx && self.want_play {
            return;
        }
        self.set_station(next);
        if self.want_play {
            self.engine.static_burst();
            self.play();
        }
    }

    pub fn tune_by(&mut self, d: isize) {
        self.tune(self.station_idx as isize + d);
    }

    /// Change tape and start playing it.
    pub fn insert(&mut self, i: usize) {
        if i != self.station_idx {
            self.set_station(i);
            self.engine.static_burst();
        }
        self.play();
    }

    fn schedule_retry(&mut self) {
        if self.retries >= 6 {
            self.status = Status::Error;
            self.want_play = false;
            self.retry_at = None;
            self.engine.stop();
            return;
        }
        self.status = Status::Loading;
        let delay = (600u64 << self.retries).min(8000);
        self.retries += 1;
        self.retry_at = Some(Instant::now() + Duration::from_millis(delay));
    }

    /* -------------------------------------------------------------- settings */

    pub fn set_sleep(&mut self, min: u32) {
        self.sleep_min = min;
        self.sleep_end = (min > 0).then(|| Instant::now() + Duration::from_secs(min as u64 * 60));
        self.fade = 1.0;
    }

    pub fn cycle_sleep(&mut self) {
        let i = SLEEP_OPTS
            .iter()
            .position(|&m| m == self.sleep_min)
            .unwrap_or(0);
        self.set_sleep(SLEEP_OPTS[(i + 1) % SLEEP_OPTS.len()]);
    }

    pub fn set_volume(&mut self, v: f32) {
        self.settings.volume = (v.clamp(0.0, 1.0) * 100.0).round() / 100.0;
        self.mark_dirty();
    }

    pub fn toggle_mute(&mut self) {
        let v = self.settings.volume;
        if v > 0.0 {
            self.last_vol = v;
        }
        self.set_volume(if v > 0.0 { 0.0 } else { self.last_vol });
    }

    pub fn toggle(&mut self, t: Toggle) {
        let s = &mut self.settings;
        let v = match t {
            Toggle::Scan => &mut s.scan,
            Toggle::Flicker => &mut s.flicker,
            Toggle::Noise => &mut s.noise,
            Toggle::Reactive => &mut s.reactive,
            Toggle::Hiss => &mut s.hiss,
        };
        *v = !*v;
        self.mark_dirty();
    }

    fn mark_dirty(&mut self) {
        self.save_at
            .get_or_insert_with(|| Instant::now() + SAVE_DELAY);
    }

    /// Write pending settings now (called on exit).
    pub fn flush_settings(&mut self) {
        if self.save_at.take().is_some() && self.persist {
            self.settings.save();
        }
    }

    pub fn toggle_fx(&mut self) {
        self.fx_open = !self.fx_open;
        self.screen = if self.screen == Screen::Fx {
            Screen::Now
        } else {
            Screen::Fx
        };
    }

    /* -------------------------------------------------------------- per-frame */

    pub fn tick(&mut self, dt: f32) {
        while let Ok(ev) = self.events.try_recv() {
            let AudioEvent::Failed(generation) = ev;
            if generation == self.engine.generation() && self.want_play {
                self.schedule_retry();
            }
        }
        if let Some(at) = self.retry_at
            && Instant::now() >= at
            && self.want_play
        {
            self.retry_at = None;
            self.start_stream();
        }

        if self.want_play {
            if self.engine.playing() {
                if self.status != Status::Playing {
                    self.status = Status::Playing;
                    self.retries = 0;
                }
            } else if self.status == Status::Playing {
                self.status = Status::Loading;
                self.loading_since = Instant::now();
            } else if self.status == Status::Loading
                && self.retry_at.is_none()
                && self.loading_since.elapsed() > Duration::from_secs(20)
            {
                // Stalled without an error: reconnect.
                self.schedule_retry();
            }
        }

        if let Some(end) = self.sleep_end {
            let left = end.saturating_duration_since(Instant::now()).as_secs_f32();
            if left <= 0.0 {
                self.set_sleep(0);
                self.pause();
            } else if left < FADE_SECS && self.want_play {
                self.fade = left / FADE_SECS;
            }
        }

        self.engine.set_volume(self.settings.volume * self.fade);
        self.engine
            .set_hiss(self.settings.hiss && self.status == Status::Playing);

        // Visuals.
        self.vis.dt = dt.min(0.1);
        self.vis.t = self.start.elapsed().as_secs_f32();
        let real = self.settings.reactive && self.status == Status::Playing;
        if real {
            self.engine.analysis(&mut self.vis.samples);
        }
        self.vis.sample(real, self.want_play);
        let target = self.view_hue();
        let k = self.vis.ease(0.07);
        self.vis.hue = approach_hue(self.vis.hue, target, k);

        if self.save_at.is_some_and(|at| Instant::now() >= at) {
            self.flush_settings();
        }

        {
            let meta = self.meta.lock_ok();
            if meta.version != self.snap.version {
                self.snap = meta.clone();
            }
        }
    }

    pub fn view_hue(&self) -> f32 {
        match self.hover {
            Some(i) => STATIONS[i].hue,
            None if !self.desktop && self.screen == Screen::Shelf => STATIONS[self.sel].hue,
            None => self.station().hue,
        }
    }

    /* -------------------------------------------------------------- data */

    pub fn now_track(&self, id: &str) -> NowTrack<'_> {
        let t = self.snap.tracks.get(id);
        NowTrack {
            title: t
                .map(|t| t.title.as_str())
                .filter(|s| !s.is_empty())
                .unwrap_or("Tuning in…"),
            artist: t
                .map(|t| t.artist.as_str())
                .filter(|s| !s.is_empty())
                .unwrap_or("Waiting for the signal"),
            elapsed: t
                .and_then(|t| t.at)
                .map(|at| epoch_ms().saturating_sub(at) as f64 / 1000.0),
        }
    }

    pub fn track(&self, id: &str) -> Option<&Track> {
        self.snap.tracks.get(id)
    }

    pub fn listeners(&self, id: &str) -> Option<u32> {
        self.snap.listeners.get(id).copied()
    }

    pub fn history(&self, id: &str) -> &[Track] {
        self.snap.history.get(id).map_or(&[], Vec::as_slice)
    }

    pub fn meta_online(&self) -> bool {
        self.snap.online
    }

    pub fn total_listeners(&self) -> u32 {
        self.snap
            .listeners
            .values()
            .fold(0u32, |a, &b| a.saturating_add(b))
    }

    pub fn status_label(&self) -> String {
        match self.status {
            Status::Loading => "TUNING".into(),
            Status::Error => "NO SIGNAL".into(),
            Status::Playing => match self.sleep_end {
                Some(end) => {
                    let left = end.saturating_duration_since(Instant::now()).as_secs_f32();
                    format!("SLEEP {}M", ((left / 60.0).ceil() as u32).max(1))
                }
                None => "ON AIR".into(),
            },
            Status::Idle => "STANDBY".into(),
            Status::Paused => "PAUSED".into(),
        }
    }

    pub fn sleep_left(&self) -> Option<f32> {
        self.sleep_end
            .map(|end| end.saturating_duration_since(Instant::now()).as_secs_f32())
    }

    /// Seconds since the last tape change (large when there was none).
    pub fn since_switch(&self) -> f32 {
        self.burst_at
            .map(|t| t.elapsed().as_secs_f32())
            .unwrap_or(99.0)
    }
}
