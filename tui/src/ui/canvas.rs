//! A tiny RGB pixel canvas rendered with half blocks (two square pixels per cell).

use crate::color::Rgb;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;

pub struct Canvas {
    pub w: usize,
    pub h: usize,
    px: Vec<Rgb>,
}

impl Canvas {
    pub fn new(w: usize, h: usize) -> Canvas {
        Canvas {
            w,
            h,
            px: vec![Rgb::default(); w * h],
        }
    }

    #[inline]
    pub fn get(&self, x: usize, y: usize) -> Rgb {
        self.px[y * self.w + x]
    }

    #[inline]
    pub fn set(&mut self, x: usize, y: usize, c: Rgb) {
        if x < self.w && y < self.h {
            self.px[y * self.w + x] = c;
        }
    }

    #[inline]
    pub fn blend(&mut self, x: i32, y: i32, c: Rgb, a: f32) {
        if x < 0 || y < 0 || x as usize >= self.w || y as usize >= self.h || a <= 0.0 {
            return;
        }
        let i = y as usize * self.w + x as usize;
        self.px[i] = self.px[i].mix(c, a);
    }

    /// Fill a shape given by a signed distance function, anti-aliased on its edge.
    /// `color` receives the pixel centre in canvas coordinates.
    pub fn fill_sdf(
        &mut self,
        bounds: (f32, f32, f32, f32),
        sdf: impl Fn(f32, f32) -> f32,
        color: impl Fn(f32, f32) -> (Rgb, f32),
    ) {
        let (x0, y0, x1, y1) = bounds;
        let (xa, ya) = (x0.floor().max(0.0) as i32, y0.floor().max(0.0) as i32);
        let (xb, yb) = (
            x1.ceil().min(self.w as f32) as i32,
            y1.ceil().min(self.h as f32) as i32,
        );
        for y in ya..yb {
            for x in xa..xb {
                let (px, py) = (x as f32 + 0.5, y as f32 + 0.5);
                let cov = (0.5 - sdf(px, py)).clamp(0.0, 1.0);
                if cov > 0.0 {
                    let (c, a) = color(px, py);
                    self.blend(x, y, c, cov * a);
                }
            }
        }
    }

    /// Draw into `area` of the buffer; canvas pixel (0,0) is the area's top-left.
    pub fn blit(&self, buf: &mut Buffer, area: Rect) {
        for row in 0..area.height as usize {
            let (y0, y1) = (row * 2, row * 2 + 1);
            if y1 >= self.h {
                break;
            }
            for col in 0..(area.width as usize).min(self.w) {
                let top = self.get(col, y0);
                let bot = self.get(col, y1);
                if let Some(cell) = buf.cell_mut((area.x + col as u16, area.y + row as u16)) {
                    cell.set_symbol("▀")
                        .set_fg(top.to_color())
                        .set_bg(bot.to_color());
                }
            }
        }
    }
}

/// Rounded rectangle distance (negative inside).
pub fn sd_round_rect(px: f32, py: f32, x0: f32, y0: f32, x1: f32, y1: f32, r: f32) -> f32 {
    let (cx, cy) = ((x0 + x1) / 2.0, (y0 + y1) / 2.0);
    let (hx, hy) = ((x1 - x0) / 2.0 - r, (y1 - y0) / 2.0 - r);
    let qx = (px - cx).abs() - hx;
    let qy = (py - cy).abs() - hy;
    let outside = (qx.max(0.0).powi(2) + qy.max(0.0).powi(2)).sqrt();
    outside + qx.max(qy).min(0.0) - r
}

pub fn sd_circle(px: f32, py: f32, cx: f32, cy: f32, r: f32) -> f32 {
    ((px - cx).powi(2) + (py - cy).powi(2)).sqrt() - r
}

/// Small deterministic PRNG so the scenery is stable between frames.
pub struct Rng(pub u64);
impl Rng {
    pub fn next(&mut self) -> f32 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        (self.0 >> 40) as f32 / (1u64 << 24) as f32
    }
}
