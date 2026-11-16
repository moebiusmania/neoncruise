//! Live outrun scene: sky, stars, striped sun, mountains and a scrolling neon grid.
//! A port of `src/components/shared/Horizon.tsx` to a half-block pixel canvas.

use super::canvas::{Canvas, Rng};
use crate::color::{Rgb, oklch};
use crate::vis::Vis;

struct Star {
    x: f32,
    y: f32,
    big: bool,
    p: f32,
    sp: f32,
}

pub struct Horizon {
    far: Vec<(f32, f32)>,
    near: Vec<(f32, f32)>,
    stars: Vec<Star>,
    star_area: usize,
    rng: Rng,
    phase: f32,
    spd: f32,
    hy: Option<f32>,
    r: Option<f32>,
}

fn ridge(rng: &mut Rng, n: usize, lo: f32) -> Vec<(f32, f32)> {
    (0..=n)
        .map(|k| {
            let x = k as f32 / n as f32;
            let e = ((x - 0.5).abs() * 2.0).powf(1.5);
            let v = if k % 2 == 1 {
                0.55 + 0.45 * rng.next()
            } else {
                lo + 0.3 * rng.next()
            };
            (x, v * (0.1 + 0.9 * e))
        })
        .collect()
}

fn ridge_at(pts: &[(f32, f32)], x: f32) -> f32 {
    let n = pts.len() - 1;
    let f = (x.clamp(0.0, 1.0)) * n as f32;
    let i = (f.floor() as usize).min(n - 1);
    let t = f - i as f32;
    pts[i].1 + (pts[i + 1].1 - pts[i].1) * t
}

pub struct Scene {
    /// Horizon line in canvas pixels.
    pub horizon: f32,
    /// Sun radius in canvas pixels.
    pub sun: f32,
    /// Vanishing point / sun centre x.
    pub cx: f32,
    pub playing: bool,
}

impl Horizon {
    pub fn new() -> Horizon {
        let mut rng = Rng(0x5eed_f00d_cafe_babe);
        let far = ridge(&mut rng, 44, 0.25);
        let near = ridge(&mut rng, 26, 0.1);
        Horizon {
            far,
            near,
            stars: vec![],
            star_area: 0,
            rng,
            phase: 0.0,
            spd: 0.5,
            hy: None,
            r: None,
        }
    }

    pub fn draw(&mut self, cv: &mut Canvas, vis: &Vis, sc: &Scene) {
        let (w, h) = (cv.w as f32, cv.h as f32);
        if w < 2.0 || h < 2.0 {
            return;
        }
        if cv.w * cv.h != self.star_area {
            self.star_area = cv.w * cv.h;
            let n = (self.star_area / 260).min(260);
            let rng = &mut self.rng;
            self.stars = (0..n)
                .map(|_| Star {
                    x: rng.next(),
                    y: rng.next(),
                    big: rng.next() < 0.15,
                    p: rng.next() * 6.0,
                    sp: 0.5 + rng.next() * 2.0,
                })
                .collect();
        }

        let k = vis.ease(0.06);
        let hy = self.hy.get_or_insert(sc.horizon);
        *hy += (sc.horizon - *hy) * k;
        let r = self.r.get_or_insert(sc.sun);
        *r += (sc.sun - *r) * k;
        let (yh, r) = (*hy, *r);
        self.spd += ((if sc.playing { 1.0 } else { 0.12 }) - self.spd) * vis.ease(0.04);
        self.phase += vis.dt * self.spd * 1.3;

        let hue = vis.hue;
        let beat = vis.beat;
        let t = vis.t;
        let cx = sc.cx;
        let top = Rgb::hex(0x04020a);
        let mid = oklch(0.17, 0.09, hue + 30.0);
        let low = oklch(0.45, 0.2, hue + 10.0);
        let glow = oklch(0.62, 0.24, hue);
        let cy = yh - r * 0.62;
        let glow_a = 0.5 + vis.level * 0.25;

        // Sky gradient and the soft glow behind the sun.
        let ys = (yh.ceil() as usize).min(cv.h);
        for y in 0..ys {
            let f = (y as f32 + 0.5) / yh;
            let base = if f < 0.55 {
                top.mix(mid, f / 0.55)
            } else {
                mid.mix(low, (f - 0.55) / 0.45)
            };
            for x in 0..cv.w {
                let d = ((x as f32 + 0.5 - cx).powi(2) + (y as f32 + 0.5 - cy).powi(2)).sqrt();
                let g = ((d - r * 0.6) / (r * 2.2)).clamp(0.0, 1.0);
                cv.set(x, y, base.mix(glow, (1.0 - g) * glow_a));
            }
        }

        for st in &self.stars {
            let y = st.y * yh * 0.85;
            let a = (0.25 + 0.75 * (t * st.sp + st.p).sin().abs())
                * (1.0 - y / yh)
                * if st.big { 0.9 } else { 0.5 };
            cv.blend((st.x * w) as i32, y as i32, Rgb(1.0, 0.94, 1.0), a);
        }

        // Sun: vertical gradient, scrolling cut-out stripes on its lower half, beat-pulsed halo.
        let sun_top = oklch(0.94, 0.12, hue + 75.0);
        let sun_mid = oklch(0.8, 0.19, hue + 35.0);
        let sun_bot = oklch(0.62, 0.26, hue);
        let halo = oklch(0.72, 0.26, hue);
        let stp = (r * 0.13).max(1.6);
        let off = (t * r * 0.047).rem_euclid(stp);
        let blur = r * (0.35 + beat * 0.3);
        let (x0, x1) = (
            (cx - r - blur).max(0.0) as usize,
            ((cx + r + blur).ceil() as usize).min(cv.w),
        );
        let (y0, y1) = (
            (cy - r - blur).max(0.0) as usize,
            ((cy + r + blur).ceil().min(yh)) as usize,
        );
        for y in y0..y1.min(cv.h) {
            let py = y as f32 + 0.5;
            let f = ((py - (cy - r)) / (2.0 * r)).clamp(0.0, 1.0);
            let col = if f < 0.5 {
                sun_top.mix(sun_mid, f * 2.0)
            } else {
                sun_mid.mix(sun_bot, (f - 0.5) * 2.0)
            };
            // Stripe coverage for this pixel row.
            let mut cut = 0.0f32;
            let dy = py - cy;
            if dy >= 0.0 {
                for k in -1..12 {
                    let sy = cy + r * 0.02 + k as f32 * stp + off;
                    let sdy = sy - cy;
                    if sdy < 0.0 {
                        continue;
                    }
                    let th = (0.5 + (sdy / r) * r * 0.075 * 0.6).min(stp * 0.8);
                    let ov = ((y as f32 + 1.0).min(sy + th) - (y as f32).max(sy)).max(0.0);
                    cut += ov;
                }
            }
            let cut = cut.min(1.0);
            for x in x0..x1 {
                let d = super::canvas::sd_circle(x as f32 + 0.5, py, cx, cy, r);
                let cov = (0.5 - d).clamp(0.0, 1.0) * (1.0 - cut);
                if d > 0.0 {
                    let a = (1.0 - d / blur.max(0.1)).max(0.0).powi(2) * 0.45;
                    cv.blend(x as i32, y as i32, halo, a);
                }
                cv.blend(x as i32, y as i32, col, cov);
            }
        }

        // Mountains: a distant ridge and a near silhouette with neon outlines.
        let mh = yh * 0.44;
        let mtn =
            |cv: &mut Canvas, pts: &[(f32, f32)], hm: f32, fill: Rgb, stroke: Rgb, sa: f32| {
                for x in 0..cv.w {
                    let fx = |px: f32| yh - ridge_at(pts, px / w) * hm;
                    let (a, b, c) = (fx(x as f32), fx(x as f32 + 0.5), fx(x as f32 + 1.0));
                    let lo = a.min(b).min(c);
                    let hi = a.max(b).max(c);
                    for y in (lo.floor().max(0.0) as usize)..(yh.ceil() as usize).min(cv.h) {
                        let (py0, py1) = (y as f32, y as f32 + 1.0);
                        let inside = (py1.min(yh) - py0.max(b)).clamp(0.0, 1.0);
                        if inside > 0.0 {
                            cv.blend(x as i32, y as i32, fill, inside);
                        }
                        let edge = (py1.min(hi + 0.55) - py0.max(lo - 0.45)).clamp(0.0, 1.0);
                        if edge > 0.0 {
                            cv.blend(x as i32, y as i32, stroke, edge * sa);
                        }
                    }
                }
            };
        mtn(
            cv,
            &self.far,
            mh * 0.62,
            oklch(0.2, 0.1, hue + 40.0),
            oklch(0.66, 0.2, hue + 20.0),
            0.5,
        );
        mtn(
            cv,
            &self.near,
            mh * 0.42,
            Rgb::hex(0x07030d),
            oklch(0.76, 0.22, hue),
            0.85,
        );

        // Floor and the grid.
        let floor_top = oklch(0.22, 0.13, hue);
        let grid = oklch(0.76, 0.22, hue);
        let fh = h - yh;
        let ph = self.phase.rem_euclid(1.0);
        let mut rows: Vec<(f32, f32, f32)> = Vec::new(); // (y, alpha, width)
        for k in 0..60 {
            let y = yh + fh * 1.2 / (k as f32 + 1.0 - ph);
            if y > h + 2.0 {
                continue;
            }
            if y - yh < 0.3 {
                break;
            }
            let a = ((y - yh) / fh * 2.2).min(1.0);
            rows.push((y, a * (0.7 + 0.3 * beat), 0.35 + a * 0.45 + beat * a * 0.35));
        }
        let spacing = (w / 14.0).max(6.0);
        let spacing_top = spacing * 1.5 / 62.0;
        for y in (yh.floor().max(0.0) as usize)..cv.h {
            let (py0, py1) = (y as f32, y as f32 + 1.0);
            let ft = ((py0 + 0.5 - yh) / fh).clamp(0.0, 1.0);
            let covered = (py1 - py0.max(yh)).clamp(0.0, 1.0);
            if covered <= 0.0 {
                continue;
            }
            let base = floor_top.mix(top, ft);
            let mut hl = 0.0f32;
            for &(ly, a, lw) in &rows {
                let ov = (py1.min(ly + lw / 2.0) - py0.max(ly - lw / 2.0)).max(0.0);
                hl += ov / lw.max(1.0) * a;
            }
            let va = if ft < 0.35 {
                ft / 0.35 * 0.5
            } else {
                0.5 + (ft - 0.35) / 0.65 * 0.45
            };
            let sp = spacing_top + (spacing - spacing_top) * ft;
            for x in 0..cv.w {
                let jf = (x as f32 + 0.5 - cx) / sp;
                let d = (jf - jf.round()).abs() * sp;
                let vcov = (1.0 - d / 0.75).max(0.0) * (0.75 / sp.max(0.75)).clamp(0.3, 1.0);
                let mut c = base.mix(grid, hl.min(1.0));
                c = c.mix(grid, vcov * va);
                let prev = cv.get(x, y);
                cv.set(x, y, prev.mix(c, covered));
            }
        }

        // Bright horizon line with a little bloom.
        let line = oklch(0.9, 0.15, hue + 40.0);
        let bloom = oklch(0.8, 0.22, hue);
        let yi = yh.floor() as i32;
        for x in 0..cv.w as i32 {
            cv.blend(x, yi - 1, bloom, 0.35);
            cv.blend(x, yi, line, 0.9);
            cv.blend(x, yi + 1, bloom, 0.3);
        }
    }
}
