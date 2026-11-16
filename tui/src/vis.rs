//! Shared per-frame visual state: spectrum bins, beat pulse and loudness.
//! Mirrors the web app's analyser setup (fftSize 512, smoothing 0.78, byte dB scale).

use crate::audio::ANALYSIS_LEN;
use rustfft::{Fft, FftPlanner, num_complex::Complex};
use std::sync::Arc;

pub const BINS: usize = ANALYSIS_LEN / 2;

pub struct Vis {
    /// Current (interpolated) scene hue.
    pub hue: f32,
    /// 0..1 pulse that spikes on kicks (or a simulated 110 BPM beat).
    pub beat: f32,
    /// 0..1 overall loudness.
    pub level: f32,
    /// Frequency bins 0..1.
    pub bins: [f32; BINS],
    /// True when `bins` holds real audio data this frame.
    pub live: bool,
    pub t: f32,
    pub dt: f32,
    fft: Arc<dyn Fft<f32>>,
    window: Vec<f32>,
    smooth: Vec<f32>,
    scratch: Vec<Complex<f32>>,
    pub samples: Vec<f32>,
    bass_avg: f32,
}

impl Vis {
    pub fn new(hue: f32) -> Vis {
        let n = ANALYSIS_LEN;
        let window = (0..n)
            .map(|i| {
                let x = i as f32 / n as f32 * std::f32::consts::TAU;
                0.42 - 0.5 * x.cos() + 0.08 * (2.0 * x).cos()
            })
            .collect();
        Vis {
            hue,
            beat: 0.0,
            level: 0.0,
            bins: [0.0; BINS],
            live: false,
            t: 0.0,
            dt: 0.0,
            fft: FftPlanner::new().plan_fft_forward(n),
            window,
            smooth: vec![0.0; BINS],
            scratch: vec![Complex::default(); n],
            samples: vec![0.0; n],
            bass_avg: 0.2,
        }
    }

    /// `real`: whether `samples` holds live audio and the analyser should be used.
    pub fn sample(&mut self, real: bool, playing: bool) {
        // Per-frame constants were tuned for 60 fps; scale them to the real frame time.
        let f = (self.dt * 60.0).max(0.1);
        if real {
            for (c, (s, w)) in self
                .scratch
                .iter_mut()
                .zip(self.samples.iter().zip(&self.window))
            {
                *c = Complex::new(s * w, 0.0);
            }
            self.fft.process(&mut self.scratch);
            let n = ANALYSIS_LEN as f32;
            for k in 0..BINS {
                let mag = self.scratch[k].norm() / n;
                self.smooth[k] = 0.78 * self.smooth[k] + 0.22 * mag;
                let db = 20.0 * self.smooth[k].max(1e-12).log10();
                self.bins[k] = ((db + 100.0) / 70.0).clamp(0.0, 1.0);
            }
            let bass = self.bins[1..7].iter().sum::<f32>() / 6.0;
            self.level = self.bins[..96].iter().sum::<f32>() / 96.0;
            self.bass_avg += (bass - self.bass_avg) * (1.0 - (0.96f32).powf(f));
            let kick = ((bass - self.bass_avg * 1.06) * 6.0).max(0.0);
            self.beat = (self.beat * 0.88f32.powf(f)).max(kick.min(1.0));
            self.live = true;
        } else {
            self.live = false;
            self.beat = if playing {
                (1.0 - (self.t * 1.833).rem_euclid(1.0)).powi(3)
            } else {
                self.beat * 0.9f32.powf(f)
            };
            let target = if playing { 0.35 } else { 0.0 };
            self.level += (target - self.level) * (1.0 - 0.95f32.powf(f));
            self.smooth.fill(0.0);
        }
    }

    /// Frame-rate independent version of the web's `x += (t - x) * k` per-frame easing.
    pub fn ease(&self, k: f32) -> f32 {
        1.0 - (1.0 - k).powf(self.dt * 60.0)
    }
}
