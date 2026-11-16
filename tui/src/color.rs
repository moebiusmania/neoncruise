//! Colour helpers: the web app defines every accent in oklch, so we do too.

use ratatui::style::Color;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Rgb(pub f32, pub f32, pub f32);

impl Rgb {
    pub const fn hex(v: u32) -> Rgb {
        Rgb(
            ((v >> 16) & 0xff) as f32 / 255.0,
            ((v >> 8) & 0xff) as f32 / 255.0,
            (v & 0xff) as f32 / 255.0,
        )
    }

    pub fn mix(self, o: Rgb, t: f32) -> Rgb {
        let t = t.clamp(0.0, 1.0);
        Rgb(
            self.0 + (o.0 - self.0) * t,
            self.1 + (o.1 - self.1) * t,
            self.2 + (o.2 - self.2) * t,
        )
    }

    pub fn scale(self, k: f32) -> Rgb {
        Rgb(self.0 * k, self.1 * k, self.2 * k)
    }

    pub fn to_color(self) -> Color {
        let q = |v: f32| (v.clamp(0.0, 1.0) * 255.0 + 0.5) as u8;
        Color::Rgb(q(self.0), q(self.1), q(self.2))
    }

    pub fn from_color(c: Color) -> Option<Rgb> {
        match c {
            Color::Rgb(r, g, b) => Some(Rgb(r as f32 / 255.0, g as f32 / 255.0, b as f32 / 255.0)),
            _ => None,
        }
    }
}

/// oklch(L C H) to gamma-encoded sRGB, clamped into gamut.
pub fn oklch(l: f32, c: f32, h: f32) -> Rgb {
    let hr = h.rem_euclid(360.0).to_radians();
    let (a, b) = (c * hr.cos(), c * hr.sin());
    let l_ = l + 0.396_337_78 * a + 0.215_803_76 * b;
    let m_ = l - 0.105_561_346 * a - 0.063_854_17 * b;
    let s_ = l - 0.089_484_18 * a - 1.291_485_5 * b;
    let (l3, m3, s3) = (l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_);
    let r = 4.076_741_7 * l3 - 3.307_711_6 * m3 + 0.230_969_94 * s3;
    let g = -1.268_438 * l3 + 2.609_757_4 * m3 - 0.341_319_38 * s3;
    let bl = -0.004_196_086_3 * l3 - 0.703_418_6 * m3 + 1.707_614_7 * s3;
    let enc = |v: f32| {
        let v = v.clamp(0.0, 1.0);
        if v <= 0.003_130_8 {
            12.92 * v
        } else {
            1.055 * v.powf(1.0 / 2.4) - 0.055
        }
    };
    Rgb(enc(r), enc(g), enc(bl))
}

pub fn ok(l: f32, c: f32, h: f32) -> Color {
    oklch(l, c, h).to_color()
}

/// Shortest-path hue interpolation (wraps around 360).
pub fn approach_hue(from: f32, to: f32, k: f32) -> f32 {
    let d = (to - from + 540.0).rem_euclid(360.0) - 180.0;
    (from + d * k).rem_euclid(360.0)
}

pub const BG: Rgb = Rgb::hex(0x05020a);
pub const INK: Color = Color::Rgb(0xf6, 0xf0, 0xfb);
pub const INK2: Color = Color::Rgb(0xbd, 0xb8, 0xc2);
pub const INK3: Color = Color::Rgb(0x8f, 0x8a, 0x95);
pub const LINE: Color = Color::Rgb(0x3a, 0x33, 0x42);
pub const GOOD: Color = Color::Rgb(0x4a, 0xde, 0x80);

/// The per-hue accent palette, mirroring the CSS custom properties.
#[derive(Clone, Copy)]
pub struct Theme {
    pub hue: f32,
    pub acc: Color,
    pub acc2: Color,
    pub line: Color,
}

impl Theme {
    pub fn new(hue: f32) -> Theme {
        Theme {
            hue,
            acc: ok(0.74, 0.19, hue),
            acc2: ok(0.88, 0.13, hue + 60.0),
            line: oklch(0.74, 0.19, hue).mix(BG, 0.62).to_color(),
        }
    }
}
