//! Rendering. The frame is built in layers like the web app: the outrun scene and
//! the cassette on a pixel canvas, glass panels on top, then text, then CRT effects.

pub mod canvas;
pub mod cassette;
pub mod font;
pub mod fx;
pub mod horizon;

use crate::app::{Action, App, SLEEP_OPTS, Screen, Status, Toggle, epoch_ms, fmt};
use crate::color::{self, BG, GOOD, INK, INK2, INK3, LINE, Rgb, Theme, ok, oklch};
use crate::stations::{STATIONS, tape_code, tape_num, total};
use canvas::{Canvas, Rng, sd_round_rect};
use horizon::{Horizon, Scene};
use ratatui::Frame;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier, Style};
use unicode_width::{UnicodeWidthChar, UnicodeWidthStr};

const RACK_W: u16 = 36;
const SIDE_W: u16 = 40;
const SPARK: [&str; 9] = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"];

pub struct Ui {
    horizon: Horizon,
    post: fx::Post,
    spec: Vec<f32>,
    seeds: Vec<f32>,
    spin: f32,
    spin_speed: f32,
    rng: Rng,
}

/// Where the stage pieces landed this frame.
struct StageLayout {
    area: Rect,
    header_y: u16,
    console: Rect,
    centered: bool,
}

/* ------------------------------------------------------------------ text helpers */

fn put(buf: &mut Buffer, x: u16, y: u16, s: &str, max: u16, style: Style) -> u16 {
    if max == 0 || y >= buf.area.bottom() {
        return 0;
    }
    let (end, _) = buf.set_stringn(x, y, s, max as usize, style);
    end.saturating_sub(x)
}

fn fg(c: Color) -> Style {
    Style::new().fg(c)
}

fn bold(c: Color) -> Style {
    Style::new().fg(c).add_modifier(Modifier::BOLD)
}

/// Truncate to `w` columns, ending with an ellipsis when cut.
fn trunc(s: &str, w: usize) -> String {
    if s.width() <= w {
        return s.to_string();
    }
    let mut out = String::new();
    let mut used = 0;
    for ch in s.chars() {
        let cw = ch.width().unwrap_or(0);
        if used + cw + 1 > w {
            break;
        }
        used += cw;
        out.push(ch);
    }
    out.push('…');
    out
}

/// Letter-spaced caps, like the CSS `letter-spacing` on display labels.
fn spaced(s: &str) -> String {
    let mut out = String::new();
    for (i, ch) in s.chars().enumerate() {
        if i > 0 {
            out.push(' ');
        }
        out.push(ch);
    }
    out
}

/// Letter-spaced when it fits in `w`, plain (and truncated if needed) otherwise.
fn fit_spaced(s: &str, w: usize) -> String {
    let sp = spaced(s);
    if sp.width() <= w { sp } else { trunc(s, w) }
}

fn rounded_box(buf: &mut Buffer, r: Rect, c: Color, title: Option<(&str, Color)>) {
    if r.width < 2 || r.height < 2 {
        return;
    }
    let st = fg(c);
    let (x0, x1, y0, y1) = (r.x, r.right() - 1, r.y, r.bottom() - 1);
    for x in x0 + 1..x1 {
        buf.set_string(x, y0, "─", st);
        buf.set_string(x, y1, "─", st);
    }
    for y in y0 + 1..y1 {
        buf.set_string(x0, y, "│", st);
        buf.set_string(x1, y, "│", st);
    }
    buf.set_string(x0, y0, "╭", st);
    buf.set_string(x1, y0, "╮", st);
    buf.set_string(x0, y1, "╰", st);
    buf.set_string(x1, y1, "╯", st);
    if let Some((t, tc)) = title {
        let t = format!(" {} ", fit_spaced(t, r.width.saturating_sub(6) as usize));
        put(buf, x0 + 2, y0, &t, r.width.saturating_sub(4), bold(tc));
    }
}

fn hline(buf: &mut Buffer, x: u16, y: u16, w: u16, c: Color) {
    for i in 0..w {
        buf.set_string(x + i, y, "─", fg(c));
    }
}

fn mix(a: Color, b: Color, t: f32) -> Color {
    let a = Rgb::from_color(a).unwrap_or(BG);
    let b = Rgb::from_color(b).unwrap_or(BG);
    a.mix(b, t).to_color()
}

fn ease_out(t: f32) -> f32 {
    1.0 - (1.0 - t.clamp(0.0, 1.0)).powi(3)
}

impl Ui {
    pub fn new() -> Ui {
        let mut rng = Rng(0xfeed_beef_1234_5678);
        let seeds = (0..256).map(|_| rng.next() * 10.0).collect();
        Ui {
            horizon: Horizon::new(),
            post: fx::Post::new(),
            spec: vec![0.0; 256],
            seeds,
            spin: 0.0,
            spin_speed: 0.0,
            rng,
        }
    }

    pub fn draw(&mut self, f: &mut Frame, app: &mut App) {
        let area = f.area();
        app.hits.clear();
        let buf = f.buffer_mut();
        for cell in buf.content.iter_mut() {
            cell.reset();
            cell.set_bg(BG.to_color());
        }
        if area.width < 40 || area.height < 16 {
            let msg = "Neon Cruise needs a bigger terminal (40×16)";
            put(buf, 0, 0, msg, area.width, fg(INK));
            return;
        }

        let desktop = area.width >= 100 && area.height >= 28;
        app.desktop = desktop;
        let wide = area.width >= 150;
        let theme = Theme::new(app.vis.hue);

        // Reels: spin up/down smoothly (1.8 s per turn when playing).
        let target = if app.want_play { 1.0 / 1.8 } else { 0.0 };
        self.spin_speed += (target - self.spin_speed) * app.vis.ease(0.08);
        self.spin += self.spin_speed * app.vis.dt;

        if desktop {
            self.draw_desktop(buf, area, app, &theme, wide);
        } else {
            self.draw_mobile(buf, area, app, &theme);
        }

        let since = app.since_switch();
        let burst = if since < 0.32 {
            1.0 - since / 0.32
        } else {
            0.0
        };
        self.post.apply(
            buf,
            &fx::PostOpts {
                scan: app.settings.scan,
                flicker: app.settings.flicker,
                noise: app.settings.noise,
                burst,
            },
        );
    }

    /* -------------------------------------------------------------- layouts */

    fn draw_desktop(
        &mut self,
        buf: &mut Buffer,
        area: Rect,
        app: &mut App,
        th: &Theme,
        wide: bool,
    ) {
        let title = Rect::new(area.x, area.y, area.width, 2);
        let status = Rect::new(area.x, area.bottom() - 1, area.width, 1);
        let body = Rect::new(area.x, area.y + 2, area.width, area.height - 3);
        let show_side = wide || app.fx_open;
        let show_rack = !(show_side && !wide && area.width < RACK_W + SIDE_W + 56);
        let rack = Rect::new(
            body.x,
            body.y,
            if show_rack { RACK_W } else { 0 },
            body.height,
        );
        let side_w = if show_side { SIDE_W } else { 0 };
        let side = Rect::new(body.right() - side_w, body.y, side_w, body.height);
        let stage = Rect::new(rack.right(), body.y, side.x - rack.right(), body.height);
        let console = Rect::new(
            stage.x + 3,
            stage.bottom().saturating_sub(8),
            stage.width.saturating_sub(6),
            7,
        );
        let sl = StageLayout {
            area: stage,
            header_y: stage.y + 1,
            console,
            centered: false,
        };

        self.scene(buf, area, app, &sl, None);

        fx::glass(buf, title, 0.14);
        fx::glass(buf, status, 0.14);
        if show_rack {
            fx::glass(buf, rack, 0.22);
        }
        if show_side {
            fx::glass(buf, side, 0.22);
        }

        self.titlebar(buf, title, app, th, !wide);
        if show_rack {
            for y in rack.top()..rack.bottom() {
                buf.set_string(rack.right() - 1, y, "│", fg(LINE));
            }
            self.rack(
                buf,
                Rect::new(rack.x, rack.y, rack.width - 1, rack.height),
                app,
                true,
            );
        }
        if show_side {
            for y in side.top()..side.bottom() {
                buf.set_string(side.x, y, "│", fg(LINE));
            }
            self.side(
                buf,
                Rect::new(side.x + 1, side.y, side.width - 1, side.height),
                app,
                th,
            );
        }
        self.stage_text(buf, &sl, app, th);
        self.statusbar(buf, status, app);
    }

    fn draw_mobile(&mut self, buf: &mut Buffer, area: Rect, app: &mut App, th: &Theme) {
        let tabs = Rect::new(area.x, area.bottom() - 1, area.width, 1);
        let top = Rect::new(area.x, area.y, area.width, 2);
        let body = Rect::new(area.x, area.y + 2, area.width, area.height - 3);
        let console = Rect::new(
            body.x + 1,
            body.bottom().saturating_sub(7),
            body.width.saturating_sub(2),
            7,
        );
        let sl = StageLayout {
            area: body,
            header_y: body.y,
            console,
            centered: true,
        };

        let horizon = match app.screen {
            Screen::Now => None,
            Screen::Shelf => Some((0.64, 0.12)),
            Screen::Fx => Some((0.3, 0.08)),
        };
        self.scene(buf, area, app, &sl, horizon);
        fx::glass(buf, top, 0.14);
        fx::glass(buf, tabs, 0.14);

        // Logo + pill.
        let x = put(
            buf,
            top.x + 2,
            top.y,
            "NEON CRUISE",
            top.width,
            bold(th.acc2),
        );
        put(
            buf,
            top.x + 3 + x,
            top.y,
            "· NIGHTRIDE FM",
            top.width,
            fg(INK2),
        );
        let label = app.status_label();
        let pw = label.width() as u16 + 4;
        self.pill(buf, top.right().saturating_sub(pw + 2), top.y, app, th);
        hline(buf, top.x, top.y + 1, top.width, LINE);

        match app.screen {
            Screen::Now => self.stage_text(buf, &sl, app, th),
            Screen::Shelf => {
                fx::glass(buf, body, 0.18);
                self.rack(buf, body, app, false);
            }
            Screen::Fx => {
                fx::glass(buf, body, 0.18);
                self.side(buf, body, app, th);
            }
        }

        // Tabs.
        let items = [
            (Screen::Now, "NOW"),
            (Screen::Shelf, "SHELF"),
            (Screen::Fx, "FX"),
        ];
        let cw = tabs.width / 3;
        for (k, (s, label)) in items.iter().enumerate() {
            let r = Rect::new(tabs.x + k as u16 * cw, tabs.y, cw, 1);
            let on = app.screen == *s;
            if on {
                fx::tint(buf, r, oklch(0.74, 0.19, th.hue), 0.22);
            }
            let t = spaced(label);
            let x = r.x + (r.width.saturating_sub(t.width() as u16)) / 2;
            put(
                buf,
                x,
                r.y,
                &t,
                r.width,
                if on { bold(th.acc) } else { fg(INK3) },
            );
            app.hits.push((r, Action::Screen(*s)));
        }
    }

    /* -------------------------------------------------------------- scenery */

    /// Paint the horizon across `full` and the cassette on the stage.
    /// `fixed` overrides the horizon (fraction of height, sun as fraction of height).
    fn scene(
        &mut self,
        buf: &mut Buffer,
        full: Rect,
        app: &App,
        sl: &StageLayout,
        fixed: Option<(f32, f32)>,
    ) {
        let mut cv = Canvas::new(full.width as usize, full.height as usize * 2);
        let stage = sl.area;
        let cx = (stage.x as f32 + stage.width as f32 / 2.0) - full.x as f32;
        let header_bottom = (sl.header_y + 8 - full.y) as f32 * 2.0;
        let region_top = header_bottom + 4.0;
        let region_bot = (sl.console.y.saturating_sub(full.y) as f32) * 2.0 - 2.0;
        let avail = region_bot - region_top;
        let mut tape_w = (stage.width as f32 * 0.4)
            .min(avail * 300.0 / 190.0)
            .min(64.0);
        if tape_w < 26.0 {
            tape_w = 0.0;
        }
        let tape_h = cassette::height(tape_w);
        let tape_y = (region_top + (avail - tape_h) * 0.55).round();
        let tape_y = tape_y - tape_y.rem_euclid(2.0);
        let tape_x = (cx - tape_w / 2.0).round();

        let h = cv.h as f32;
        let (yh, sun) = match fixed {
            Some((fy, fs)) => (h * fy, h * fs),
            None => {
                let yh = if tape_w > 0.0 { tape_y + 2.0 } else { h * 0.56 };
                let yh = yh.clamp(h * 0.35, h * 0.75);
                let r = ((yh - header_bottom) / 1.75).clamp(4.0, stage.width as f32 * 0.17);
                (yh, r)
            }
        };
        self.horizon.draw(
            &mut cv,
            &app.vis,
            &Scene {
                horizon: yh,
                sun,
                cx,
                playing: app.want_play,
            },
        );

        let show_tape = fixed.is_none() && tape_w > 0.0;
        let mut label = None;
        if show_tape {
            // Deck slot above the tape.
            let (sx0, sx1) = (cx - tape_w * 0.46, cx + tape_w * 0.46);
            let (sy0, sy1) = (tape_y - 4.0, tape_y - 2.0);
            let slot = Rgb::hex(0x07030d);
            cv.fill_sdf(
                (sx0, sy0, sx1, sy1),
                |x, y| sd_round_rect(x, y, sx0, sy0, sx1, sy1, 1.0),
                |_, _| (slot, 0.95),
            );

            // Fresh tape slides into the deck.
            let since = app.since_switch();
            let slide = (1.0 - ease_out(since / 0.55)) * (tape_h * 0.6);
            let now = app.now_track(app.station().id);
            let spot = cassette::draw(
                &mut cv,
                &cassette::Tape {
                    x: tape_x,
                    y: tape_y + slide.round() - (slide.round()).rem_euclid(2.0),
                    w: tape_w,
                    hue: app.station().hue,
                    progress: now.progress,
                    spin: self.spin,
                },
            );
            label = Some(spot);
        }
        cv.blit(buf, full);

        // Label text printed on the cassette.
        if let Some(spot) = label {
            let row = full.y + (spot.y / 2.0) as u16;
            let (x0, x1) = (full.x + spot.x0.ceil() as u16, full.x + spot.x1 as u16);
            let hue = app.station().hue;
            let lab = oklch(0.96, 0.025, hue + 40.0).to_color();
            let ink = Rgb::hex(0x140a18).to_color();
            for x in x0..x1 {
                if let Some(c) = buf.cell_mut((x, row)) {
                    c.set_symbol(" ").set_bg(lab).set_fg(lab);
                }
            }
            let name = trunc(&spaced(app.station().name), (x1 - x0) as usize);
            let code = tape_code(app.station_idx);
            let w = x1 - x0;
            put(buf, x0, row, &name, w, bold(ink).bg(lab));
            if name.width() + code.len() + 2 <= w as usize {
                put(
                    buf,
                    x1 - code.len() as u16,
                    row,
                    &code,
                    w,
                    fg(ok(0.52, 0.22, hue)).bg(lab),
                );
            }
        }
    }

    /* -------------------------------------------------------------- pieces */

    fn pill(&self, buf: &mut Buffer, x: u16, y: u16, app: &App, th: &Theme) -> u16 {
        let label = app.status_label();
        let t = app.vis.t;
        let dot = match app.status {
            Status::Playing => GOOD,
            Status::Loading => {
                if (t * 3.0).sin() > 0.0 {
                    th.acc
                } else {
                    mix(th.acc, color::BG.to_color(), 0.7)
                }
            }
            Status::Error => Color::Rgb(0xff, 0x5a, 0x6a),
            _ => INK3,
        };
        let w = label.width() as u16 + 4;
        fx::tint(buf, Rect::new(x, y, w, 1), oklch(0.74, 0.19, th.hue), 0.12);
        put(buf, x, y, "▕", w, fg(th.line));
        put(buf, x + 1, y, "●", w, fg(dot));
        put(buf, x + 3, y, &label, w, bold(INK));
        put(buf, x + w - 1, y, "▏", w, fg(th.line));
        w
    }

    fn titlebar(&self, buf: &mut Buffer, r: Rect, app: &mut App, th: &Theme, fx_chip: bool) {
        // NEON CRUISE with a warm gradient, like the web logo.
        let logo = spaced("NEON CRUISE");
        let mut x = r.x + 2;
        let n = logo.chars().count().max(1) as f32;
        for (i, ch) in logo.chars().enumerate() {
            let c = mix(ok(0.86, 0.14, 60.0), th.acc, i as f32 / n);
            buf.set_string(x, r.y, ch.to_string(), bold(c));
            x += 1;
        }
        x += 2;
        put(buf, x, r.y, "│", 1, fg(LINE));
        x += 3;
        x += put(buf, x, r.y, &spaced("NIGHTRIDE"), 40, bold(INK));
        put(buf, x + 2, r.y, "F M", 4, bold(th.acc));

        let label = app.status_label();
        let pw = label.width() as u16 + 4;
        self.pill(buf, r.x + (r.width - pw) / 2, r.y, app, th);

        if fx_chip {
            let chip = " ◈ FX ";
            let cx = r.right() - chip.width() as u16 - 2;
            let cr = Rect::new(cx, r.y, chip.width() as u16, 1);
            if app.fx_open {
                fx::tint(buf, cr, oklch(0.74, 0.19, th.hue), 0.35);
            }
            put(
                buf,
                cx,
                r.y,
                chip,
                10,
                bold(if app.fx_open { INK } else { INK2 }),
            );
            app.hits.push((cr, Action::Fx));
        }
        hline(buf, r.x, r.y + 1, r.width, LINE);
    }

    fn rack(&self, buf: &mut Buffer, r: Rect, app: &mut App, desktop: bool) {
        let cur = app.station_idx;
        let sel = if desktop { None } else { Some(app.sel) };
        let x0 = r.x + 2;
        let w = r.width.saturating_sub(4);
        let head_hue = sel.map(|s| STATIONS[s].hue).unwrap_or(app.vis.hue);
        put(buf, x0, r.y + 1, &spaced("TAPE SHELF"), w, bold(INK));
        let count = format!("{}/{}", tape_num(cur), total());
        put(
            buf,
            r.right().saturating_sub(count.len() as u16 + 2),
            r.y + 1,
            &count,
            8,
            fg(ok(0.74, 0.19, head_hue)),
        );

        let start = r.y + 3;
        let t = app.vis.t;
        for (i, st) in STATIONS.iter().enumerate() {
            let y = start + i as u16 * 3;
            if y + 2 > r.bottom().saturating_sub(2) {
                break;
            }
            let active = i == cur;
            let playing = active && app.want_play;
            let hl = active || sel == Some(i) || app.hover == Some(i);
            let item = Rect::new(r.x + 1, y, r.width.saturating_sub(2), 2);
            let acc = ok(0.74, 0.19, st.hue);
            if hl {
                fx::tint(
                    buf,
                    item,
                    oklch(0.74, 0.19, st.hue),
                    if active { 0.16 } else { 0.09 },
                );
            }
            if sel == Some(i) {
                put(buf, item.x, y, "▸", 1, bold(acc));
            }
            // Spine: the coloured edge of the tape, with its code.
            let spine_a = ok(0.72, 0.17, st.hue);
            let spine_b = ok(0.55, 0.2, st.hue);
            for (k, c) in [spine_a, spine_b].iter().enumerate() {
                for dx in 0..2 {
                    if let Some(cell) = buf.cell_mut((x0 + dx, y + k as u16)) {
                        cell.set_symbol(" ").set_bg(*c);
                    }
                }
            }

            let tx = x0 + 3;
            let n = put(buf, tx, y, &tape_num(i), 3, fg(acc));
            let nw = r.right().saturating_sub(tx + n + 1 + 8) as usize;
            put(
                buf,
                tx + n + 1,
                y,
                &fit_spaced(st.name, nw),
                nw as u16,
                bold(if hl { INK } else { INK2 }),
            );

            // Right meta: equaliser when playing, else listeners.
            let mw = 5u16;
            let mx = r.right().saturating_sub(mw + 2);
            if playing {
                let eq = [(0.9, 0.0), (0.7, 0.3), (1.1, 0.5), (0.8, 0.15)];
                for (k, (dur, delay)) in eq.iter().enumerate() {
                    let ph = ((t + delay) / dur).rem_euclid(2.0);
                    let tri = if ph < 1.0 { ph } else { 2.0 - ph };
                    let e = 0.5 - 0.5 * (tri * std::f32::consts::PI).cos();
                    let lvl = (1.0 + e * 7.0).round() as usize;
                    put(buf, mx + 1 + k as u16, y, SPARK[lvl.min(8)], 1, fg(acc));
                }
            } else if let Some(n) = app.listeners(st.id) {
                let s = format!("• {n}");
                put(
                    buf,
                    r.right().saturating_sub(s.width() as u16 + 2),
                    y + 1,
                    &s,
                    mw + 2,
                    fg(INK3),
                );
            }

            let now = app
                .track(st.id)
                .map(|t| {
                    if t.artist.is_empty() {
                        t.title
                    } else {
                        format!("{} — {}", t.artist, t.title)
                    }
                })
                .unwrap_or_else(|| st.tag.to_string());
            let nw = (r.right().saturating_sub(tx + 8)) as usize;
            put(
                buf,
                tx,
                y + 1,
                &trunc(&now, nw),
                nw as u16,
                fg(if hl {
                    ok(0.88, 0.1, st.hue + 40.0)
                } else {
                    INK3
                }),
            );
            app.hits.push((item, Action::Select(i)));
        }

        let hint = if desktop {
            "Click a tape · 1–7 · ←→ tune"
        } else {
            "↑↓ choose · ENTER slot in · 1–7"
        };
        hline(buf, r.x, r.bottom().saturating_sub(2), r.width, LINE);
        put(buf, x0, r.bottom() - 1, hint, w, fg(INK3));
    }

    fn stage_text(&mut self, buf: &mut Buffer, sl: &StageLayout, app: &mut App, th: &Theme) {
        let st = app.station();
        let i = app.station_idx;
        let a = sl.area;
        let pad = 4u16;
        let inner_w = a.width.saturating_sub(pad * 2);
        let center = |w: u16| {
            if sl.centered {
                a.x + (a.width.saturating_sub(w)) / 2
            } else {
                a.x + pad
            }
        };

        // TAPE 01 / 07 · SIDE A · 22 TUNED IN
        let mut tape = spaced(&format!("TAPE {} / {} · SIDE A", tape_num(i), total()));
        let tuned = app
            .listeners(st.id)
            .map(|n| format!("   ·   {}", spaced(&format!("{n} TUNED IN"))));
        if let Some(tu) = &tuned
            && tape.width() + tu.width() > inner_w as usize
        {
            tape = format!("TAPE {} / {} · SIDE A", tape_num(i), total());
        }
        let full_w = (tape.width() + tuned.as_ref().map_or(0, |s| s.width())) as u16;
        let x = center(full_w.min(inner_w));
        let n = put(buf, x, sl.header_y, &tape, inner_w, bold(th.acc));
        if let Some(tu) = tuned {
            put(
                buf,
                x + n,
                sl.header_y,
                &tu,
                inner_w.saturating_sub(n),
                fg(INK2),
            );
        }

        // Station name: big pixel letters that scramble in after a tape change.
        let since = app.since_switch();
        let mut name: String = String::new();
        let chars: Vec<char> = font::CHARS.chars().collect();
        for (k, ch) in st.name.chars().enumerate() {
            let reveal = 0.12 + k as f32 * 0.045;
            if since < reveal {
                let r = (self.rng.next() * chars.len() as f32) as usize % chars.len();
                name.push(chars[r]);
            } else {
                name.push(ch);
            }
        }
        let ny = sl.header_y + 2;
        let fade = ease_out(since / 0.4);
        let big_w = font::width(&name, 1);
        if big_w <= inner_w {
            let x = center(big_w);
            let top = mix(BG.to_color(), INK, 0.3 + 0.7 * fade);
            let bot = mix(BG.to_color(), th.acc, 0.3 + 0.7 * fade);
            font::draw(buf, x, ny, &name, 1, a.right(), |_, row| match row {
                0 => top,
                1 => mix(top, bot, 0.5),
                _ => bot,
            });
        } else {
            let s = spaced(&name);
            put(
                buf,
                center(s.width() as u16),
                ny + 1,
                &s,
                inner_w,
                bold(INK),
            );
        }
        let tag = trunc(st.tag, inner_w as usize);
        put(
            buf,
            center(tag.width() as u16),
            ny + 4,
            &tag,
            inner_w,
            fg(INK2),
        );

        self.console(buf, sl.console, app, th);
    }

    fn console(&mut self, buf: &mut Buffer, r: Rect, app: &mut App, th: &Theme) {
        if r.width < 30 || r.height < 7 {
            return;
        }
        fx::glass(buf, r, 0.25);
        rounded_box(buf, r, th.line, None);
        let now = app.now_track(app.station().id);
        let inner = Rect::new(r.x + 2, r.y + 1, r.width - 4, r.height - 2);

        // Transport on the right: ◀◀  ▶/❚❚  ▶▶ as little keycaps.
        let bw = [6u16, 8, 6];
        let tw = bw.iter().sum::<u16>() + 2;
        let show_transport = inner.width >= tw + 20;
        let text_w = if show_transport {
            inner.width - tw - 2
        } else {
            inner.width
        };
        if show_transport {
            let mut x = inner.right() - tw;
            let playing = app.want_play;
            let loading = app.status == Status::Loading;
            let buttons = [
                ("◀◀", Action::Prev, false),
                (if playing { "❚❚" } else { "▶" }, Action::TogglePlay, true),
                ("▶▶", Action::Next, false),
            ];
            for (k, (sym, act, main)) in buttons.iter().enumerate() {
                let br = Rect::new(x, inner.y, bw[k], 3);
                if *main {
                    let pulse = if loading {
                        0.6 + 0.4 * (app.vis.t * 5.0).sin().abs()
                    } else {
                        1.0
                    };
                    let c = oklch(0.74, 0.19, th.hue).scale(pulse);
                    fx::tint(buf, br, c, 0.92);
                    let glow_c = mix(th.acc, INK, 0.3);
                    rounded_box(buf, br, glow_c, None);
                    let sx = br.x + (br.width - sym.width() as u16) / 2;
                    put(
                        buf,
                        sx,
                        br.y + 1,
                        sym,
                        3,
                        bold(Rgb::hex(0x140a18).to_color()),
                    );
                } else {
                    rounded_box(buf, br, LINE, None);
                    put(buf, br.x + 2, br.y + 1, sym, 2, bold(INK));
                }
                app.hits.push((br, *act));
                x += bw[k] + 1;
            }
        }

        put(
            buf,
            inner.x,
            inner.y,
            &trunc(&now.title, text_w as usize),
            text_w,
            bold(INK),
        );
        put(
            buf,
            inner.x,
            inner.y + 1,
            &trunc(&now.artist, text_w as usize),
            text_w,
            fg(th.acc2),
        );

        // Timeline: elapsed · spectrum · LIVE.
        let y = inner.bottom() - 1;
        let pos = &now.pos;
        put(buf, inner.x, y, pos, 8, fg(INK3));
        let live = "L I V E";
        put(
            buf,
            inner.right() - live.len() as u16,
            y,
            live,
            8,
            bold(th.acc),
        );
        let sx = inner.x + pos.len() as u16 + 2;
        let sw = inner
            .width
            .saturating_sub(pos.len() as u16 + live.len() as u16 + 4);
        self.spectrum(buf, Rect::new(sx, y - 1, sw, 2), app);
    }

    fn spectrum(&mut self, buf: &mut Buffer, r: Rect, app: &App) {
        let bars = (r.width as usize).min(self.spec.len());
        if bars == 0 {
            return;
        }
        let vis = &app.vis;
        let t = vis.t;
        let n = vis.bins.len();
        for i in 0..bars {
            let v = if vis.live {
                // Log-ish mapping so the low end isn't crammed into two bars.
                let f0 = ((i as f32 / bars as f32).powf(1.7) * n as f32 * 0.7) as usize;
                let f1 = (((i + 1) as f32 / bars as f32).powf(1.7) * n as f32 * 0.7) as usize;
                let f1 = f1.max(f0 + 1).min(n);
                vis.bins[f0..f1].iter().sum::<f32>() / (f1 - f0) as f32
            } else if app.want_play {
                let env = 1.0 - i as f32 / bars as f32;
                (0.25 + 0.35 * (t * 2.3 + self.seeds[i]).sin().abs())
                    * (0.4 + 0.6 * env)
                    * (0.6 + 0.4 * vis.beat)
            } else {
                0.0
            };
            let hgt = &mut self.spec[i];
            *hgt += (v - *hgt) * vis.ease(if v > *hgt { 0.6 } else { 0.15 });
        }
        let rows = r.height as f32;
        for i in 0..bars {
            let hv = self.spec[i];
            let units = (hv * rows * 8.0).round().max(1.0) as usize;
            let c = oklch(0.7 + hv * 0.2, 0.19, vis.hue)
                .mix(BG, 0.55 - hv * 0.55)
                .to_color();
            for row in 0..r.height {
                let from_bottom = (r.height - 1 - row) as usize;
                let lvl = units.saturating_sub(from_bottom * 8).min(8);
                if lvl > 0 {
                    put(buf, r.x + i as u16, r.y + row, SPARK[lvl], 1, fg(c));
                }
            }
        }
    }

    fn side(&self, buf: &mut Buffer, r: Rect, app: &mut App, th: &Theme) {
        let x0 = r.x + 1;
        let w = r.width.saturating_sub(2);
        put(buf, x0 + 1, r.y + 1, &spaced("SIGNAL FX"), w, bold(INK));
        let mut y = r.y + 3;
        let bottom = r.bottom();

        // FX toggles.
        let rows = [
            (
                Toggle::Scan,
                "SCANLINES",
                "CRT raster across the app",
                app.settings.scan,
            ),
            (
                Toggle::Flicker,
                "FLICKER",
                "Unstable tube brightness",
                app.settings.flicker,
            ),
            (
                Toggle::Noise,
                "NOISE",
                "Analog grain on screen",
                app.settings.noise,
            ),
        ];
        // Drop the descriptions when the panel is short, so every card still fits.
        let compact = r.height < 40;
        let step = if compact { 1 } else { 3 };
        let h = if compact {
            rows.len() as u16 + 2
        } else {
            rows.len() as u16 * 3 + 1
        };
        if y + h <= bottom {
            let card = Rect::new(x0, y, w, h);
            rounded_box(buf, card, LINE, None);
            for (k, (tg, label, desc, on)) in rows.iter().enumerate() {
                let ry = y + 1 + k as u16 * step;
                self.toggle_row(
                    buf,
                    Rect::new(x0 + 2, ry, w - 4, if compact { 1 } else { 2 }),
                    label,
                    desc,
                    *on,
                    th,
                    app,
                    Action::Toggle(*tg),
                );
            }
            y += h + 1;
        }

        // Sleep timer.
        let h = 9;
        if y + h <= bottom {
            let card = Rect::new(x0, y, w, h);
            rounded_box(buf, card, LINE, Some(("SLEEP TIMER", INK)));
            let left = app.sleep_left();
            let mins = left.map(|l| (l / 60.0).ceil() as u32).unwrap_or(0);
            let digits = format!("{:03}", mins.min(999));
            let dc = if left.is_some() {
                th.acc
            } else {
                mix(th.acc, BG.to_color(), 0.35)
            };
            font::draw(buf, x0 + 2, y + 1, &digits, 1, card.right() - 1, |_, _| dc);
            put(
                buf,
                x0 + 2 + font::width(&digits, 1) + 2,
                y + 3,
                "M I N",
                6,
                fg(INK3),
            );
            let note = match (app.sleep_end, left) {
                (Some(_), Some(l)) => {
                    let at = epoch_ms() / 1000 + l as u64;
                    let local = local_hm(at);
                    format!("Tape fades out at {local} · {} left", fmt(l as f64))
                }
                _ => "Plays until you stop it".into(),
            };
            put(
                buf,
                x0 + 2,
                y + 5,
                &trunc(&note, (w - 4) as usize),
                w - 4,
                fg(INK2),
            );
            let seg_w = ((w - 4) / SLEEP_OPTS.len() as u16).max(4);
            for (k, m) in SLEEP_OPTS.iter().enumerate() {
                let sr = Rect::new(x0 + 2 + k as u16 * seg_w, y + 7, seg_w - 1, 1);
                let on = app.sleep_min == *m;
                fx::tint(
                    buf,
                    sr,
                    if on {
                        oklch(0.74, 0.19, th.hue)
                    } else {
                        Rgb(1.0, 1.0, 1.0)
                    },
                    if on { 0.9 } else { 0.06 },
                );
                let label = if *m == 0 {
                    "OFF".to_string()
                } else {
                    m.to_string()
                };
                let lx = sr.x + (sr.width.saturating_sub(label.len() as u16)) / 2;
                put(
                    buf,
                    lx,
                    sr.y,
                    &label,
                    sr.width,
                    if on {
                        bold(Rgb::hex(0x140a18).to_color())
                    } else {
                        fg(INK2)
                    },
                );
                app.hits.push((sr, Action::Sleep(*m)));
            }
            y += h + 1;
        }

        // Audio.
        let h = if compact { 5 } else { 9 };
        if y + h <= bottom {
            let card = Rect::new(x0, y, w, h);
            rounded_box(buf, card, LINE, Some(("AUDIO", INK)));
            let vol = app.settings.volume;
            let mr = Rect::new(x0 + 2, y + 1, 3, 1);
            put(
                buf,
                mr.x,
                mr.y,
                if vol == 0.0 { "MUT" } else { "VOL" },
                3,
                bold(th.acc),
            );
            app.hits.push((mr, Action::Mute));
            let slider = Rect::new(x0 + 6, y + 1, w.saturating_sub(13), 1);
            let filled = ((slider.width - 1) as f32 * vol).round() as u16;
            for k in 0..slider.width {
                let (s, c) = if k == filled {
                    ("●", INK)
                } else if k < filled {
                    ("━", th.acc)
                } else {
                    ("─", LINE)
                };
                put(buf, slider.x + k, slider.y, s, 1, fg(c));
            }
            app.hits.push((slider, Action::Volume));
            put(
                buf,
                slider.right() + 1,
                y + 1,
                &format!("{:03}", (vol * 100.0).round() as u32),
                3,
                fg(INK3),
            );
            let th_ = if compact { 1 } else { 2 };
            let rx = Rect::new(x0 + 2, y + if compact { 2 } else { 3 }, w - 4, th_);
            self.toggle_row(
                buf,
                rx,
                "REACTIVE",
                "Grid and spectrum follow the real audio",
                app.settings.reactive,
                th,
                app,
                Action::Toggle(Toggle::Reactive),
            );
            let hx = Rect::new(x0 + 2, y + if compact { 3 } else { 6 }, w - 4, th_);
            self.toggle_row(
                buf,
                hx,
                "TAPE HISS",
                "Mix faint analog hiss into the stream",
                app.settings.hiss,
                th,
                app,
                Action::Toggle(Toggle::Hiss),
            );
            y += h + 1;
        }

        // On-air log.
        if y + 4 <= bottom {
            let card = Rect::new(x0, y, w, bottom - y);
            let title = format!("ON-AIR LOG · {}", app.station().name);
            rounded_box(buf, card, LINE, Some((&title, INK)));
            let log = app.history(app.station().id);
            let mut ly = y + 1;
            if log.is_empty() {
                put(
                    buf,
                    x0 + 2,
                    ly,
                    "Listening for track changes…",
                    w - 4,
                    fg(INK3),
                );
            }
            for (k, t) in log.iter().enumerate() {
                if ly + 2 > card.bottom() - 1 {
                    break;
                }
                let idx = if k == 0 {
                    "NOW".to_string()
                } else {
                    format!("{k:02}")
                };
                put(
                    buf,
                    x0 + 2,
                    ly,
                    &idx,
                    3,
                    if k == 0 { bold(th.acc) } else { fg(INK3) },
                );
                let tw = w.saturating_sub(9) as usize;
                put(
                    buf,
                    x0 + 7,
                    ly,
                    &trunc(&t.title, tw),
                    tw as u16,
                    fg(if k == 0 { INK } else { INK2 }),
                );
                put(
                    buf,
                    x0 + 7,
                    ly + 1,
                    &trunc(&t.artist, tw),
                    tw as u16,
                    fg(if k == 0 { th.acc2 } else { INK3 }),
                );
                ly += 2;
            }
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn toggle_row(
        &self,
        buf: &mut Buffer,
        r: Rect,
        label: &str,
        desc: &str,
        on: bool,
        th: &Theme,
        app: &mut App,
        act: Action,
    ) {
        let sw = 5u16;
        let tw = r.width.saturating_sub(sw + 1);
        put(buf, r.x, r.y, &spaced(label), tw, bold(INK));
        if r.height > 1 {
            put(buf, r.x, r.y + 1, &trunc(desc, tw as usize), tw, fg(INK3));
        }
        let sr = Rect::new(r.right() - sw, r.y, sw, 1);
        if on {
            fx::tint(buf, sr, oklch(0.74, 0.19, th.hue), 0.95);
            put(buf, sr.right() - 2, sr.y, "●", 1, fg(INK));
        } else {
            fx::tint(buf, sr, Rgb(1.0, 1.0, 1.0), 0.12);
            put(buf, sr.x + 1, sr.y, "●", 1, fg(INK2));
        }
        app.hits.push((r, act));
    }

    fn statusbar(&self, buf: &mut Buffer, r: Rect, app: &App) {
        let mut x = r.x + 2;
        let y = r.y;
        let dot = |ok: bool| if ok { GOOD } else { INK3 };
        let st = app.status;
        let stream = if st == Status::Playing {
            "STREAM 320 KBPS · MP3".to_string()
        } else {
            format!("STREAM {:?}", st).to_uppercase()
        };
        let (online, total) = {
            let m = app.meta.lock().unwrap();
            (m.online, m.listeners.values().sum::<u32>())
        };
        let item = |buf: &mut Buffer, x: &mut u16, d: Option<Color>, s: &str, c: Color| {
            if let Some(d) = d {
                put(buf, *x, y, "●", 1, fg(d));
                *x += 2;
            }
            *x += put(buf, *x, y, s, r.right().saturating_sub(*x), fg(c)) + 3;
        };
        item(buf, &mut x, Some(dot(st == Status::Playing)), &stream, INK2);
        item(
            buf,
            &mut x,
            Some(dot(online)),
            if online { "META LIVE" } else { "META OFFLINE" },
            INK2,
        );
        if !app.engine.available {
            item(
                buf,
                &mut x,
                Some(Color::Rgb(0xff, 0x5a, 0x6a)),
                "NO AUDIO DEVICE",
                INK2,
            );
        }
        if total > 0 && r.width > 110 {
            item(
                buf,
                &mut x,
                None,
                &format!("{total} LISTENERS ON THE NETWORK"),
                INK3,
            );
        }
        if app.sleep_end.is_some() {
            item(
                buf,
                &mut x,
                None,
                "SLEEP ARMED",
                ok(0.88, 0.13, app.vis.hue + 60.0),
            );
        }
        let keys: [(&str, &str); 5] = [
            ("SPACE", "PLAY"),
            ("←→", "TUNE"),
            ("M", "MUTE"),
            ("F", "FX"),
            ("Q", "QUIT"),
        ];
        let kw: u16 = keys
            .iter()
            .map(|(k, l)| k.width() as u16 + l.len() as u16 + 4)
            .sum();
        let mut kx = r.right().saturating_sub(kw + 1);
        if kx > x {
            for (k, l) in keys {
                kx += put(
                    buf,
                    kx,
                    y,
                    &format!(" {k} "),
                    8,
                    Style::new().fg(INK).bg(Rgb::hex(0x2a2430).to_color()),
                );
                kx += put(buf, kx + 1, y, l, 6, fg(INK3)) + 2;
            }
        }
    }
}

/// Local HH:MM for an epoch-seconds timestamp (uses the system's `date` offset once).
fn local_hm(epoch_s: u64) -> String {
    use std::sync::OnceLock;
    static OFFSET: OnceLock<i64> = OnceLock::new();
    let off = *OFFSET.get_or_init(|| {
        std::process::Command::new("date")
            .arg("+%z")
            .output()
            .ok()
            .and_then(|o| String::from_utf8(o.stdout).ok())
            .and_then(|s| {
                let s = s.trim();
                let sign = if s.starts_with('-') { -1 } else { 1 };
                let d = s.trim_start_matches(['+', '-']);
                let (h, m) = (
                    d.get(0..2)?.parse::<i64>().ok()?,
                    d.get(2..4)?.parse::<i64>().ok()?,
                );
                Some(sign * (h * 3600 + m * 60))
            })
            .unwrap_or(0)
    });
    let t = (epoch_s as i64 + off).rem_euclid(86_400);
    format!("{:02}:{:02}", t / 3600, (t % 3600) / 60)
}
