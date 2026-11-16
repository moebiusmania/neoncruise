//! Audio engine: an HTTP MP3 stream decoded with symphonia into a ring buffer,
//! played through one long-lived rodio source that also mixes tape hiss and
//! the static burst, and taps the signal for the spectrum analyser.

use rodio::{ChannelCount, SampleRate, Source};
use std::collections::VecDeque;
use std::io::Read;
use std::num::NonZero;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering::Relaxed};
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::errors::Error as SymError;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::{MediaSourceStream, ReadOnlySource};
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

pub const RATE: u32 = 44_100;
/// Interleaved stereo samples to hold before starting playback.
const PRIME: usize = RATE as usize; // 0.5 s
/// Back-pressure ceiling for the decoder.
const MAX_BUF: usize = RATE as usize * 2 * 4; // 4 s
pub const ANALYSIS_LEN: usize = 512;

struct AtomicF32(AtomicU32);
impl AtomicF32 {
    fn new(v: f32) -> Self {
        Self(AtomicU32::new(v.to_bits()))
    }
    fn get(&self) -> f32 {
        f32::from_bits(self.0.load(Relaxed))
    }
    fn set(&self, v: f32) {
        self.0.store(v.to_bits(), Relaxed)
    }
}

struct Shared {
    buf: Mutex<VecDeque<f32>>,
    /// Bumped on every new stream; decoder threads exit when theirs is stale.
    generation: AtomicU64,
    primed: AtomicBool,
    volume: AtomicF32,
    hiss: AtomicBool,
    burst: AtomicBool,
    /// Last ANALYSIS_LEN mono samples that went to the speakers.
    analysis: Mutex<Vec<f32>>,
}

pub enum AudioEvent {
    /// The stream failed or ended (with its generation).
    Failed(u64),
}

pub struct Engine {
    shared: Arc<Shared>,
    events: Sender<AudioEvent>,
    _sink: Option<rodio::MixerDeviceSink>,
    pub available: bool,
}

impl Engine {
    pub fn new(events: Sender<AudioEvent>, volume: f32) -> Engine {
        let shared = Arc::new(Shared {
            buf: Mutex::new(VecDeque::with_capacity(MAX_BUF + 8192)),
            generation: AtomicU64::new(0),
            primed: AtomicBool::new(false),
            volume: AtomicF32::new(volume),
            hiss: AtomicBool::new(false),
            burst: AtomicBool::new(false),
            analysis: Mutex::new(vec![0.0; ANALYSIS_LEN]),
        });
        let sink = open_sink().ok().map(|mut s| {
            s.log_on_drop(false);
            s.mixer().add(Output::new(shared.clone()));
            s
        });
        Engine {
            available: sink.is_some(),
            shared,
            events,
            _sink: sink,
        }
    }

    /// Start streaming `url`. Returns the generation of the new stream.
    pub fn play(&self, url: String) -> u64 {
        let generation = self.shared.generation.fetch_add(1, Relaxed) + 1;
        self.flush();
        let shared = self.shared.clone();
        let events = self.events.clone();
        thread::spawn(move || {
            // Errors and clean ends both mean "reconnect" unless a newer stream took over.
            let _ = stream(&shared, generation, &url);
            if shared.generation.load(Relaxed) == generation {
                let _ = events.send(AudioEvent::Failed(generation));
            }
        });
        generation
    }

    /// Stop and drop the live buffer, so resuming jumps back to "now".
    pub fn stop(&self) {
        self.shared.generation.fetch_add(1, Relaxed);
        self.flush();
    }

    fn flush(&self) {
        self.shared.buf.lock().unwrap().clear();
        self.shared.primed.store(false, Relaxed);
    }

    pub fn generation(&self) -> u64 {
        self.shared.generation.load(Relaxed)
    }

    /// True while real audio is reaching the speakers.
    pub fn playing(&self) -> bool {
        self.shared.primed.load(Relaxed)
    }

    pub fn set_volume(&self, v: f32) {
        self.shared.volume.set(v.clamp(0.0, 1.0));
    }

    pub fn set_hiss(&self, on: bool) {
        self.shared.hiss.store(on, Relaxed);
    }

    /// Short burst of radio static when changing tapes.
    pub fn static_burst(&self) {
        self.shared.burst.store(true, Relaxed);
    }

    pub fn analysis(&self, out: &mut [f32]) {
        let a = self.shared.analysis.lock().unwrap();
        out.copy_from_slice(&a[..out.len()]);
    }
}

/// Open the default output. Some devices (e.g. Bluetooth headphones on macOS)
/// reject rodio's fixed 50 ms buffer, so let the OS pick before falling back.
fn open_sink() -> Result<rodio::MixerDeviceSink, rodio::DeviceSinkError> {
    rodio::DeviceSinkBuilder::from_default_device()
        .and_then(|b| {
            b.with_buffer_size(rodio::cpal::BufferSize::Default)
                .open_stream()
        })
        .or_else(|_| rodio::DeviceSinkBuilder::open_default_sink())
}

/// `ReadOnlySource` wants `Sync`; a mutex makes any `Send` reader qualify.
struct SyncRead<R>(Mutex<R>);
impl<R: Read> Read for SyncRead<R> {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        self.0.get_mut().unwrap().read(buf)
    }
}

fn stream(shared: &Shared, generation: u64, url: &str) -> anyhow::Result<()> {
    let live = || shared.generation.load(Relaxed) == generation;
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_connect(Some(Duration::from_secs(10)))
        .timeout_recv_response(Some(Duration::from_secs(10)))
        .build()
        .into();
    let resp = agent
        .get(url)
        .header(
            "User-Agent",
            concat!("neoncruise-tui/", env!("CARGO_PKG_VERSION")),
        )
        .call()?;
    let reader = SyncRead(Mutex::new(resp.into_body().into_reader()));
    let mss = MediaSourceStream::new(Box::new(ReadOnlySource::new(reader)), Default::default());
    let mut hint = Hint::new();
    hint.with_extension("mp3");
    let probed = symphonia::default::get_probe().format(
        &hint,
        mss,
        &FormatOptions::default(),
        &MetadataOptions::default(),
    )?;
    let mut format = probed.format;
    let track = format
        .default_track()
        .ok_or_else(|| anyhow::anyhow!("no audio track"))?;
    let track_id = track.id;
    let mut decoder =
        symphonia::default::get_codecs().make(&track.codec_params, &DecoderOptions::default())?;
    let mut samples: Option<SampleBuffer<f32>> = None;
    let mut resampler = Resampler::default();
    let mut out = Vec::with_capacity(8192);

    while live() {
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(SymError::ResetRequired) => {
                decoder.reset();
                continue;
            }
            Err(e) => return Err(e.into()),
        };
        if packet.track_id() != track_id {
            continue;
        }
        let decoded = match decoder.decode(&packet) {
            Ok(d) => d,
            Err(SymError::DecodeError(_)) | Err(SymError::IoError(_)) => continue,
            Err(e) => return Err(e.into()),
        };
        let spec = *decoded.spec();
        let sb = match &mut samples {
            Some(sb) if sb.capacity() >= decoded.capacity() * spec.channels.count() => sb,
            slot => slot.insert(SampleBuffer::new(decoded.capacity() as u64, spec)),
        };
        sb.copy_interleaved_ref(decoded);
        out.clear();
        resampler.push(sb.samples(), spec.channels.count(), spec.rate, &mut out);

        loop {
            if !live() {
                return Ok(());
            }
            let mut buf = shared.buf.lock().unwrap();
            if buf.len() < MAX_BUF {
                buf.extend(out.iter().copied());
                break;
            }
            drop(buf);
            thread::sleep(Duration::from_millis(25));
        }
    }
    Ok(())
}

/// Converts any channel layout to stereo and any rate to 44.1 kHz (linear).
#[derive(Default)]
struct Resampler {
    pos: f64,
    prev: (f32, f32),
}

impl Resampler {
    fn push(&mut self, input: &[f32], ch: usize, rate: u32, out: &mut Vec<f32>) {
        let frame = |i: usize| -> (f32, f32) {
            let l = input[i * ch];
            let r = if ch > 1 { input[i * ch + 1] } else { l };
            (l, r)
        };
        let n = input.len() / ch.max(1);
        if rate == RATE {
            for i in 0..n {
                let (l, r) = frame(i);
                out.push(l);
                out.push(r);
            }
            return;
        }
        let step = rate as f64 / RATE as f64;
        // Position is relative to the previous chunk's last frame (index -1).
        while self.pos < n as f64 - 1.0 {
            let i = self.pos.floor();
            let t = (self.pos - i) as f32;
            let a = if i < 0.0 {
                self.prev
            } else {
                frame(i as usize)
            };
            let b = frame((i + 1.0) as usize);
            out.push(a.0 + (b.0 - a.0) * t);
            out.push(a.1 + (b.1 - a.1) * t);
            self.pos += step;
        }
        self.pos -= n as f64;
        if n > 0 {
            self.prev = frame(n - 1);
        }
    }
}

/// The one source that lives for the whole session.
struct Output {
    shared: Arc<Shared>,
    chunk: Vec<f32>,
    pos: usize,
    gain: f32,
    rng: u32,
    hiss_lp: f32,
    hiss_hp: f32,
    hiss_gain: f32,
    burst_env: f32,
    burst_lp: f32,
    burst_bp: f32,
    tap: Vec<f32>,
}

const CHUNK: usize = 1024;

impl Output {
    fn new(shared: Arc<Shared>) -> Output {
        Output {
            shared,
            chunk: vec![0.0; CHUNK],
            pos: CHUNK,
            gain: 0.0,
            rng: 0x9e37_79b9,
            hiss_lp: 0.0,
            hiss_hp: 0.0,
            hiss_gain: 0.0,
            burst_env: 0.0,
            burst_lp: 0.0,
            burst_bp: 0.0,
            tap: Vec::with_capacity(CHUNK / 2),
        }
    }

    fn noise(&mut self) -> f32 {
        self.rng ^= self.rng << 13;
        self.rng ^= self.rng >> 17;
        self.rng ^= self.rng << 5;
        (self.rng as f32 / u32::MAX as f32) * 2.0 - 1.0
    }

    fn refill(&mut self) {
        let sh = self.shared.clone();
        let target = sh.volume.get();
        let hiss_on = sh.hiss.load(Relaxed);
        if sh.burst.swap(false, Relaxed) {
            self.burst_env = 1.0;
        }

        // Pull a chunk of stream audio, or silence while (re)buffering.
        let mut got = 0;
        {
            let mut buf = sh.buf.lock().unwrap();
            let primed = sh.primed.load(Relaxed);
            if !primed && buf.len() >= PRIME {
                sh.primed.store(true, Relaxed);
            }
            if sh.primed.load(Relaxed) {
                got = buf.len().min(CHUNK);
                for (dst, s) in self.chunk.iter_mut().zip(buf.drain(..got)) {
                    *dst = s;
                }
                if got < CHUNK {
                    sh.primed.store(false, Relaxed);
                }
            }
        }
        self.chunk[got..].fill(0.0);

        self.tap.clear();
        let hiss_target = if hiss_on && got > 0 {
            0.018 * target
        } else {
            0.0
        };
        let burst_decay = (0.0001f32).ln() / (0.45 * RATE as f32);
        let burst_decay = burst_decay.exp();
        for f in 0..CHUNK / 2 {
            self.gain += (target - self.gain) * 0.002;
            self.hiss_gain += (hiss_target - self.hiss_gain) * 0.0005;
            let (l, r) = (self.chunk[f * 2], self.chunk[f * 2 + 1]);
            self.tap.push((l + r) * 0.5);

            // Hiss: white noise, high-passed around 3.8 kHz and softened on top.
            let n = self.noise();
            self.hiss_hp += (n - self.hiss_hp) * 0.42;
            let hp = n - self.hiss_hp;
            self.hiss_lp += (hp - self.hiss_lp) * 0.8;
            let hiss = self.hiss_lp * self.hiss_gain;

            // Static burst: band-passed noise with a fast exponential decay.
            let mut burst = 0.0;
            if self.burst_env > 0.0001 {
                let n = self.noise();
                self.burst_lp += (n - self.burst_lp) * 0.3;
                self.burst_bp += (self.burst_lp - self.burst_bp) * 0.1;
                burst = (self.burst_lp - self.burst_bp) * self.burst_env * 0.09 * target * 3.0;
                self.burst_env *= burst_decay;
            }

            self.chunk[f * 2] = l * self.gain + hiss + burst;
            self.chunk[f * 2 + 1] = r * self.gain + hiss + burst;
        }

        let mut a = sh.analysis.lock().unwrap();
        let n = self.tap.len().min(ANALYSIS_LEN);
        a.rotate_left(n);
        let len = a.len();
        a[len - n..].copy_from_slice(&self.tap[self.tap.len() - n..]);
        self.pos = 0;
    }
}

impl Iterator for Output {
    type Item = rodio::Sample;
    fn next(&mut self) -> Option<Self::Item> {
        if self.pos >= CHUNK {
            self.refill();
        }
        let s = self.chunk[self.pos];
        self.pos += 1;
        Some(s as rodio::Sample)
    }
}

impl Source for Output {
    fn current_span_len(&self) -> Option<usize> {
        None
    }
    fn channels(&self) -> ChannelCount {
        NonZero::new(2).unwrap()
    }
    fn sample_rate(&self) -> SampleRate {
        NonZero::new(RATE).unwrap()
    }
    fn total_duration(&self) -> Option<Duration> {
        None
    }
}
