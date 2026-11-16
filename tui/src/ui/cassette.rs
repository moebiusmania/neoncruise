//! The cassette, drawn on the same 300 × 190 grid as the CSS version.

use super::canvas::{Canvas, sd_circle, sd_round_rect};
use crate::color::{Rgb, oklch};
use std::f32::consts::TAU;

pub struct Tape {
    /// Top-left in canvas pixels.
    pub x: f32,
    pub y: f32,
    /// Width in canvas pixels (height follows the 300:190 ratio).
    pub w: f32,
    pub hue: f32,
    /// 0..1 how far the tape has wound from the left reel to the right.
    pub progress: f32,
    /// Reel rotation in turns.
    pub spin: f32,
}

/// Where the label text goes, in canvas pixels.
pub struct LabelSpot {
    pub x0: f32,
    pub x1: f32,
    pub y: f32,
}

pub fn height(w: f32) -> f32 {
    w * 190.0 / 300.0
}

pub fn draw(cv: &mut Canvas, t: &Tape) -> LabelSpot {
    let u = t.w / 300.0;
    let (ox, oy, h) = (t.x, t.y, t.hue);
    let p = |gx: f32, gy: f32| (ox + gx * u, oy + gy * u);

    // Neon glow and a drop shadow behind the body.
    let glow = oklch(0.6, 0.22, h);
    let (bx0, by0) = p(0.0, 0.0);
    let (bx1, by1) = p(300.0, 190.0);
    let spread = 44.0 * u;
    cv.fill_sdf(
        (bx0 - spread, by0 - spread, bx1 + spread, by1 + spread),
        |x, y| sd_round_rect(x, y, bx0, by0, bx1, by1, 12.0 * u) - spread,
        |x, y| {
            let d = sd_round_rect(x, y, bx0, by0, bx1, by1, 12.0 * u).max(0.0);
            (glow, (1.0 - d / spread).max(0.0).powi(2) * 0.45)
        },
    );

    // Body: diagonal gradient.
    let c0 = oklch(0.76, 0.16, h);
    let c1 = oklch(0.5, 0.2, h);
    cv.fill_sdf(
        (bx0, by0, bx1, by1),
        |x, y| sd_round_rect(x, y, bx0, by0, bx1, by1, 12.0 * u),
        |x, y| {
            let f =
                ((x - bx0) / (bx1 - bx0) * 0.35 + (y - by0) / (by1 - by0) * 0.65).clamp(0.0, 1.0);
            (c0.mix(c1, f), 1.0)
        },
    );
    // Top highlight.
    let hl = Rgb(1.0, 1.0, 1.0);
    for x in (bx0 + 10.0 * u) as i32..(bx1 - 10.0 * u) as i32 {
        cv.blend(x, by0 as i32, hl, 0.25);
    }

    // Screws.
    let screw = Rgb(0.0, 0.0, 0.0);
    for (sx, sy) in [(8.5, 8.5), (291.5, 8.5), (8.5, 181.5), (291.5, 181.5)] {
        let (cx, cy) = p(sx, sy);
        let rr = (3.5 * u).max(0.6);
        cv.fill_sdf(
            (cx - 2.0, cy - 2.0, cx + 2.0, cy + 2.0),
            |x, y| sd_circle(x, y, cx, cy, rr),
            |_, _| (screw, 0.35),
        );
    }

    // Label.
    let (lx0, ly0) = p(14.0, 12.0);
    let (lx1, ly1) = p(286.0, 134.0);
    let label = oklch(0.96, 0.025, h + 40.0);
    cv.fill_sdf(
        (lx0, ly0, lx1, ly1),
        |x, y| sd_round_rect(x, y, lx0, ly0, lx1, ly1, 6.0 * u),
        |_, _| (label, 1.0),
    );

    // Stripes under the label head.
    let bands = [
        (0.0, 0.3, oklch(0.72, 0.19, h)),
        (0.42, 0.66, oklch(0.84, 0.14, h + 50.0)),
        (0.78, 1.0, oklch(0.6, 0.22, h - 20.0)),
    ];
    let (sx0, sy0) = p(24.0, 42.0);
    let (sx1, sy1) = p(276.0, 54.0);
    for y in sy0.floor() as i32..sy1.ceil() as i32 {
        for (a, b, c) in bands {
            let (ya, yb) = (sy0 + (sy1 - sy0) * a, sy0 + (sy1 - sy0) * b);
            let ov = ((y as f32 + 1.0).min(yb) - (y as f32).max(ya)).clamp(0.0, 1.0);
            for x in sx0 as i32..sx1 as i32 {
                cv.blend(x, y, c, ov);
            }
        }
    }

    // Window.
    let (wx0, wy0) = p(46.0, 62.0);
    let (wx1, wy1) = p(254.0, 126.0);
    let win = Rgb::hex(0x0b0610);
    cv.fill_sdf(
        (wx0, wy0, wx1, wy1),
        |x, y| sd_round_rect(x, y, wx0, wy0, wx1, wy1, (wy1 - wy0) / 2.0),
        |_, _| (win, 1.0),
    );

    // Tape packs and reels.
    let pack_c = oklch(0.3, 0.04, 40.0);
    let hub_c = oklch(0.95, 0.02, h + 40.0);
    let rcy = oy + 94.0 * u;
    let reels = [(80.0, 1.0 - t.progress), (220.0, t.progress)];
    // Tape running between the packs at the bottom of the window.
    let ty = rcy + 22.0 * u;
    for x in p(80.0, 0.0).0 as i32..p(220.0, 0.0).0 as i32 {
        cv.blend(x, ty as i32, pack_c, 0.8);
    }
    for (gx, amt) in reels {
        let cx = ox + gx * u;
        let pack_r = (13.0 + amt * 15.0) * u;
        cv.fill_sdf(
            (
                cx - pack_r - 1.0,
                rcy - pack_r - 1.0,
                cx + pack_r + 1.0,
                rcy + pack_r + 1.0,
            ),
            |x, y| sd_circle(x, y, cx, rcy, pack_r),
            |_, _| (pack_c, 1.0),
        );
        let hub = 12.0 * u;
        cv.fill_sdf(
            (
                cx - hub - 1.0,
                rcy - hub - 1.0,
                cx + hub + 1.0,
                rcy + hub + 1.0,
            ),
            |x, y| sd_circle(x, y, cx, rcy, hub),
            |_, _| (hub_c, 1.0),
        );
        // Spokes cut into the hub, rotating.
        let a0 = t.spin * TAU;
        cv.fill_sdf(
            (
                cx - hub - 1.0,
                rcy - hub - 1.0,
                cx + hub + 1.0,
                rcy + hub + 1.0,
            ),
            |x, y| {
                let (dx, dy) = (x - cx, y - rcy);
                let r = (dx * dx + dy * dy).sqrt();
                let ang = dy.atan2(dx) - a0;
                let sector = (ang.rem_euclid(TAU / 3.0) - TAU / 6.0).abs();
                // Gaps between three spokes, plus the centre hole.
                let gap = if r < hub * 0.35 || (r < hub * 0.85 && sector < 0.55) {
                    -1.0
                } else {
                    1.0
                };
                gap * (hub * 0.1).max(0.5)
            },
            |_, _| (win, 1.0),
        );
    }

    // Head (trapezoid at the bottom) with its holes.
    let head_c = oklch(0.36, 0.15, h);
    let (hx0, hy0) = p(62.0, 150.0);
    let (hx1, hy1) = p(238.0, 190.0);
    for y in hy0.floor() as i32..hy1.ceil() as i32 {
        let f = ((y as f32 + 0.5 - hy0) / (hy1 - hy0)).clamp(0.0, 1.0);
        let inset = (hx1 - hx0) * 0.09 * (1.0 - f);
        let ov = ((y as f32 + 1.0).min(hy1) - (y as f32).max(hy0)).clamp(0.0, 1.0);
        for x in (hx0 + inset) as i32..(hx1 - inset).ceil() as i32 {
            cv.blend(x, y, head_c, ov);
        }
    }
    let hole = Rgb::hex(0x0b0610);
    let hy = oy + 172.0 * u;
    for gx in [100.0, 133.0, 167.0, 200.0] {
        let cx = ox + gx * u;
        let r = (4.0 * u).max(0.7);
        cv.fill_sdf(
            (cx - 2.0, hy - 2.0, cx + 2.0, hy + 2.0),
            |x, y| sd_circle(x, y, cx, hy, r),
            |_, _| (hole, 0.9),
        );
    }

    LabelSpot {
        x0: ox + 24.0 * u,
        x1: ox + 276.0 * u,
        y: oy + 26.0 * u,
    }
}
