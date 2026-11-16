//! Neon Cruise TUI: a retro outrun cassette player for Nightride FM, in the terminal.

mod app;
mod audio;
mod color;
mod meta;
mod settings;
mod stations;
mod sync;
mod ui;
mod vis;

use app::{Action, App, Screen};
use crossterm::event::{
    self, DisableFocusChange, DisableMouseCapture, EnableFocusChange, EnableMouseCapture, Event,
    KeyCode, KeyEventKind, KeyModifiers, MouseButton, MouseEvent, MouseEventKind,
};
use crossterm::execute;
use std::io::stdout;
use std::time::{Duration, Instant};

/// Default frame rate; `--fps N` overrides it (lower = less CPU and terminal I/O).
const FPS: u64 = 30;
/// Frame rate while the terminal window is unfocused (if the terminal reports focus).
/// Every frame repaints most of the screen in truecolor, which is real CPU and I/O.
const FPS_UNFOCUSED: u64 = 10;

fn main() -> anyhow::Result<()> {
    if std::env::args().any(|a| a == "-h" || a == "--help") {
        println!(
            "neoncruise-tui {}\n\nA retro outrun cassette player for Nightride FM.\n\nOptions:\n  --fps <N>   Frame rate, 1-60 (default {FPS}); try 15 on a Raspberry Pi or over SSH\n  -h, --help  Show this help\n\nRun it in a truecolor terminal; press ? inside for keys.",
            env!("CARGO_PKG_VERSION")
        );
        return Ok(());
    }
    let fps = match parse_fps(std::env::args()) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("neoncruise-tui: {e}");
            std::process::exit(2);
        }
    };
    #[cfg(debug_assertions)]
    if let Some(i) = std::env::args().position(|a| a == "--snapshot") {
        return snapshot(&std::env::args().skip(i + 1).collect::<Vec<_>>());
    }
    let meta = meta::start();
    let mut app = App::new(meta);
    let mut terminal = ratatui::init();
    // ratatui's panic hook restores raw mode and the alternate screen, but not the mouse and
    // focus reporting we turn on, which would leave the shell spewing escape codes on a panic.
    let hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let _ = execute!(stdout(), DisableMouseCapture, DisableFocusChange);
        hook(info);
    }));
    execute!(stdout(), EnableMouseCapture, EnableFocusChange)?;
    let res = run(&mut terminal, &mut app, fps);
    let _ = execute!(stdout(), DisableMouseCapture, DisableFocusChange);
    ratatui::restore();
    app.engine.stop();
    app.flush_settings();
    res
}

/// Read `--fps N` / `--fps=N` (1..=60), defaulting to [`FPS`].
fn parse_fps(mut args: impl Iterator<Item = String>) -> anyhow::Result<u64> {
    while let Some(a) = args.next() {
        let v = if a == "--fps" {
            args.next()
        } else if let Some(v) = a.strip_prefix("--fps=") {
            Some(v.to_string())
        } else {
            continue;
        };
        return match v.as_deref().map(str::parse::<u64>) {
            Some(Ok(n @ 1..=60)) => Ok(n),
            _ => anyhow::bail!("--fps expects a number from 1 to 60"),
        };
    }
    Ok(FPS)
}

fn run(terminal: &mut ratatui::DefaultTerminal, app: &mut App, fps: u64) -> anyhow::Result<()> {
    let mut ui = ui::Ui::new();
    let mut focused = true;
    let mut last = Instant::now();
    while !app.quit {
        let frame =
            Duration::from_millis(1000 / if focused { fps } else { fps.min(FPS_UNFOCUSED) });
        let now = Instant::now();
        let dt = (now - last).as_secs_f32();
        last = now;
        app.tick(dt);
        terminal.draw(|f| ui.draw(f, app))?;

        let deadline = now + frame;
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            if !event::poll(left)? {
                break;
            }
            match event::read()? {
                Event::Key(k) if k.kind != KeyEventKind::Release => {
                    on_key(app, k.code, k.modifiers)
                }
                Event::Mouse(m) => on_mouse(app, m),
                Event::FocusGained => focused = true,
                Event::FocusLost => focused = false,
                _ => {}
            }
            if app.quit {
                break;
            }
        }
    }
    Ok(())
}

fn on_key(app: &mut App, code: KeyCode, mods: KeyModifiers) {
    let shelf = !app.desktop && app.screen == Screen::Shelf;
    match code {
        KeyCode::Char('c') if mods.contains(KeyModifiers::CONTROL) => app.quit = true,
        KeyCode::Char('q') => app.quit = true,
        KeyCode::Char(' ') | KeyCode::Char('k') => app.toggle_play(),
        KeyCode::Enter if shelf => {
            app.insert(app.sel);
            app.screen = Screen::Now;
        }
        KeyCode::Enter => app.toggle_play(),
        KeyCode::Up if shelf => app.sel = stations::wrap_index(app.sel as isize - 1),
        KeyCode::Down if shelf => app.sel = stations::wrap_index(app.sel as isize + 1),
        KeyCode::Right | KeyCode::Down | KeyCode::Char('n') => app.tune_by(1),
        KeyCode::Left | KeyCode::Up | KeyCode::Char('p') => app.tune_by(-1),
        KeyCode::Char(c @ '1'..='9') => {
            let i = c as usize - '1' as usize;
            if i < stations::STATIONS.len() {
                app.tune(i as isize);
            }
        }
        KeyCode::Char('m') => app.toggle_mute(),
        KeyCode::Char('+') | KeyCode::Char('=') => app.set_volume(app.settings.volume + 0.05),
        KeyCode::Char('-') | KeyCode::Char('_') => app.set_volume(app.settings.volume - 0.05),
        KeyCode::Char('f') => app.toggle_fx(),
        KeyCode::Char('s') => app.cycle_sleep(),
        KeyCode::Char('r') => app.toggle(app::Toggle::Reactive),
        KeyCode::Char('h') => app.toggle(app::Toggle::Hiss),
        KeyCode::Tab => {
            app.screen = match app.screen {
                Screen::Now => Screen::Shelf,
                Screen::Shelf => Screen::Fx,
                Screen::Fx => Screen::Now,
            };
            app.sel = app.station_idx;
        }
        KeyCode::Esc => {
            app.fx_open = false;
            app.screen = Screen::Now;
        }
        _ => {}
    }
}

fn on_mouse(app: &mut App, m: MouseEvent) {
    let hit = app
        .hits
        .iter()
        .rev()
        .find(|(r, _)| {
            m.column >= r.x && m.column < r.right() && m.row >= r.y && m.row < r.bottom()
        })
        .copied();
    match m.kind {
        MouseEventKind::Moved => {
            app.hover = match hit {
                Some((_, Action::Select(i))) if app.desktop => Some(i),
                _ => None,
            };
        }
        MouseEventKind::ScrollUp => app.set_volume(app.settings.volume + 0.05),
        MouseEventKind::ScrollDown => app.set_volume(app.settings.volume - 0.05),
        MouseEventKind::Down(MouseButton::Left) | MouseEventKind::Drag(MouseButton::Left) => {
            let Some((r, act)) = hit else { return };
            let drag = matches!(m.kind, MouseEventKind::Drag(_));
            if drag && !matches!(act, Action::Volume) {
                return;
            }
            match act {
                Action::Select(i) => {
                    if app.desktop || app.sel == i {
                        app.insert(i);
                        if !app.desktop {
                            app.screen = Screen::Now;
                        }
                    } else {
                        app.sel = i;
                    }
                }
                Action::TogglePlay => app.toggle_play(),
                Action::Prev => app.tune_by(-1),
                Action::Next => app.tune_by(1),
                Action::Toggle(t) => app.toggle(t),
                Action::Sleep(min) => app.set_sleep(min),
                Action::Volume => {
                    let v = (m.column - r.x) as f32 / (r.width.max(2) - 1) as f32;
                    app.set_volume(v);
                }
                Action::Mute => app.toggle_mute(),
                Action::Screen(s) => {
                    app.screen = s;
                    app.sel = app.station_idx;
                }
                Action::Fx => app.toggle_fx(),
            }
        }
        _ => {}
    }
}

/// Debug helper: render a few seconds headlessly and dump the last frame as ANSI.
/// `--snapshot 170x48 <seconds> <out> [keys]` (playback is muted).
#[cfg(debug_assertions)]
fn snapshot(args: &[String]) -> anyhow::Result<()> {
    use ratatui::backend::TestBackend;
    use ratatui::style::Color;
    use std::fmt::Write;
    let (w, h) = args[0]
        .split_once('x')
        .ok_or_else(|| anyhow::anyhow!("size"))?;
    let secs: f32 = args[1].parse()?;
    let mut app = App::new(meta::start());
    app.persist = false;
    app.settings.volume = 0.0;
    let mut term = ratatui::Terminal::new(TestBackend::new(w.parse()?, h.parse()?))?;
    let mut ui = ui::Ui::new();
    let keys = args.get(3).cloned().unwrap_or_default();
    let start = Instant::now();
    let mut last = start;
    let mut sent = 0;
    while start.elapsed().as_secs_f32() < secs {
        let el = start.elapsed().as_secs_f32();
        // One key every 0.5 s.
        if sent < keys.len() && el > 0.5 * (sent + 1) as f32 {
            let c = keys.as_bytes()[sent] as char;
            let code = match c {
                '>' => KeyCode::Right,
                '<' => KeyCode::Left,
                '\t' => KeyCode::Tab,
                _ => KeyCode::Char(c),
            };
            on_key(&mut app, code, KeyModifiers::NONE);
            sent += 1;
        }
        let now = Instant::now();
        app.tick((now - last).as_secs_f32());
        last = now;
        term.draw(|f| ui.draw(f, &mut app))?;
        std::thread::sleep(Duration::from_millis(1000 / FPS));
    }
    let buf = term.backend().buffer().clone();
    let mut out = String::new();
    let rgb = |c: Color| match c {
        Color::Rgb(r, g, b) => (r, g, b),
        _ => (5, 2, 10),
    };
    for y in 0..buf.area.height {
        for x in 0..buf.area.width {
            let c = &buf[(x, y)];
            let (fr, fg, fb) = rgb(c.fg);
            let (br, bg, bb) = rgb(c.bg);
            let _ = write!(
                out,
                "\x1b[38;2;{fr};{fg};{fb};48;2;{br};{bg};{bb}m{}",
                c.symbol()
            );
        }
        out.push_str("\x1b[0m\n");
    }
    std::fs::write(&args[2], out)?;
    eprintln!(
        "status={:?} live={} beat={:.2} audio={}",
        app.status, app.vis.live, app.vis.beat, app.engine.available
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fps(args: &[&str]) -> anyhow::Result<u64> {
        parse_fps(args.iter().map(|s| s.to_string()))
    }

    #[test]
    fn parses_fps_flag() {
        assert_eq!(fps(&["bin"]).unwrap(), FPS);
        assert_eq!(fps(&["bin", "--fps", "15"]).unwrap(), 15);
        assert_eq!(fps(&["bin", "--fps=60"]).unwrap(), 60);
        assert!(fps(&["bin", "--fps", "0"]).is_err());
        assert!(fps(&["bin", "--fps", "120"]).is_err());
        assert!(fps(&["bin", "--fps"]).is_err());
        assert!(fps(&["bin", "--fps", "fast"]).is_err());
    }
}
