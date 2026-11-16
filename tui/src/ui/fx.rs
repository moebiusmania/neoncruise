//! Screen-space effects applied to the finished frame: glass panels, scanlines,
//! flicker, grain, the static burst on tape change and a vignette.

use super::canvas::Rng;
use crate::color::{BG, Rgb};
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Color;

const GLYPHS: [&str; 6] = ["░", "▒", "▓", "·", ":", "▚"];

/// Turn a patch of half-block scenery into a dim, flat "frosted glass" panel.
/// `keep` is how much of the scene shows through.
pub fn glass(buf: &mut Buffer, area: Rect, keep: f32) {
    let area = area.intersection(buf.area);
    for y in area.top()..area.bottom() {
        for x in area.left()..area.right() {
            let cell = &mut buf[(x, y)];
            let top = Rgb::from_color(cell.fg).unwrap_or(BG);
            let bot = Rgb::from_color(cell.bg).unwrap_or(BG);
            let c = BG.mix(top.mix(bot, 0.5), keep);
            cell.set_symbol(" ")
                .set_fg(c.to_color())
                .set_bg(c.to_color());
        }
    }
}

/// Fill a rect with a solid background (keeps symbols that are already there).
pub fn tint(buf: &mut Buffer, area: Rect, color: Rgb, a: f32) {
    let area = area.intersection(buf.area);
    for y in area.top()..area.bottom() {
        for x in area.left()..area.right() {
            let cell = &mut buf[(x, y)];
            let bg = Rgb::from_color(cell.bg).unwrap_or(BG);
            cell.set_bg(bg.mix(color, a).to_color());
        }
    }
}

pub struct Post {
    rng: Rng,
    flicker: f32,
    flicker_frames: u32,
    /// Vignette factor per cell, rebuilt only when the terminal size changes
    /// (it was a `powf` per cell per frame).
    vignette: Vec<f32>,
    vignette_size: (u16, u16),
}

pub struct PostOpts {
    pub scan: bool,
    pub flicker: bool,
    pub noise: bool,
    /// 0..1 strength of the tape-change static.
    pub burst: f32,
}

fn map(c: Color, k: f32, add: f32) -> Color {
    match Rgb::from_color(c) {
        Some(rgb) => Rgb(rgb.0 * k + add, rgb.1 * k + add, rgb.2 * k + add).to_color(),
        None => c,
    }
}

impl Post {
    pub fn new() -> Post {
        Post {
            rng: Rng(0x1234_5678_9abc_def1),
            flicker: 1.0,
            flicker_frames: 0,
            vignette: Vec::new(),
            vignette_size: (0, 0),
        }
    }

    fn vignette(&mut self, area: Rect) {
        if self.vignette_size == (area.width, area.height) {
            return;
        }
        self.vignette_size = (area.width, area.height);
        let (w, h) = (area.width as f32, area.height as f32);
        self.vignette.clear();
        for y in 0..area.height {
            let ny = (y as f32 + 0.5) / h * 2.0 - 1.0;
            for x in 0..area.width {
                let nx = (x as f32 + 0.5) / w * 2.0 - 1.0;
                self.vignette
                    .push(1.0 - 0.3 * ((nx * nx + ny * ny) / 2.0).powf(1.6));
            }
        }
    }

    pub fn apply(&mut self, buf: &mut Buffer, o: &PostOpts) {
        // Flicker: occasional short brightness dips, like an unstable tube.
        if o.flicker {
            if self.flicker_frames > 0 {
                self.flicker_frames -= 1;
            } else if self.rng.next() < 0.035 {
                self.flicker = 0.88 + self.rng.next() * 0.08;
                self.flicker_frames = 1 + (self.rng.next() * 3.0) as u32;
            } else {
                self.flicker = 1.0;
            }
        } else {
            self.flicker = 1.0;
        }

        let area = buf.area;
        self.vignette(area);
        let w = area.width as usize;
        for y in area.top()..area.bottom() {
            let scan = if o.scan && y % 2 == 1 { 0.86 } else { 1.0 };
            let row = (y - area.top()) as usize * w;
            for x in area.left()..area.right() {
                let vig = self.vignette[row + (x - area.left()) as usize];
                let mut k = scan * vig * self.flicker;
                let mut add = 0.0;
                if o.noise && self.rng.next() < 0.01 {
                    add = (self.rng.next() - 0.5) * 0.06;
                }
                let cell = &mut buf[(x, y)];
                if o.burst > 0.0 && self.rng.next() < o.burst * 0.4 {
                    let g = GLYPHS[(self.rng.next() * GLYPHS.len() as f32) as usize % GLYPHS.len()];
                    let v = 0.4 + self.rng.next() * 0.5;
                    cell.set_symbol(g).set_fg(Rgb(v, v * 0.95, v).to_color());
                    k *= 1.0 - o.burst * 0.3;
                }
                cell.fg = map(cell.fg, k, add);
                cell.bg = map(cell.bg, k, add * 0.5);
            }
        }
    }
}
