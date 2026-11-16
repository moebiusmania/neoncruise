//! Now-playing metadata: the Nightride FM SSE feed plus the Icecast status JSON.

use crate::stations::{META_URL, STATIONS, status_url};
use crate::sync::LockExt;
use serde::Deserialize;
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

const HISTORY_MAX: usize = 15;
/// Upper bound for any string taken off the network.
const TEXT_MAX: usize = 300;
/// Longest SSE line we accept; anything longer is a broken or hostile feed.
const LINE_MAX: u64 = 64 * 1024;
/// Reconnect the SSE feed if it goes completely silent for this long
/// (a dead NAT mapping or Wi-Fi switch otherwise leaves the read blocked forever).
const SSE_IDLE: Duration = Duration::from_secs(300);
const UA: &str = concat!("neoncruise-tui/", env!("CARGO_PKG_VERSION"));

#[derive(Clone, Debug)]
pub struct Track {
    pub title: String,
    pub artist: String,
    /// Epoch ms when the track started, if known.
    pub at: Option<u64>,
    pub id: Option<String>,
}

impl Track {
    fn same(&self, o: &Track) -> bool {
        matches!((&self.id, &o.id), (Some(a), Some(b)) if a == b)
            || (self.title.eq_ignore_ascii_case(&o.title)
                && self.artist.eq_ignore_ascii_case(&o.artist))
    }
}

#[derive(Default, Clone)]
pub struct MetaState {
    pub tracks: HashMap<String, Track>,
    pub history: HashMap<String, Vec<Track>>,
    pub listeners: HashMap<String, u32>,
    pub online: bool,
    /// Bumped on every change, so readers can cache a snapshot instead of locking each frame.
    pub version: u64,
}

pub type Meta = Arc<Mutex<MetaState>>;

/// Keep printable text only and cap its length. ratatui already drops control characters
/// when drawing, but this also strips bidi overrides (visual spoofing) and keeps one bad
/// frame from bloating memory.
fn clean(s: &str) -> String {
    s.chars()
        .filter(|c| {
            !c.is_control() && !matches!(c, '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')
        })
        .take(TEXT_MAX)
        .collect::<String>()
        .trim()
        .to_string()
}

#[derive(Deserialize)]
struct MetaEvent {
    station: String,
    #[serde(default)]
    title: String,
    #[serde(default)]
    artist: String,
    track_id: Option<String>,
    at: Option<u64>,
}

fn known(id: &str) -> bool {
    STATIONS.iter().any(|s| s.id == id)
}

fn push_track(st: &mut MetaState, station: &str, t: Track) {
    if let Some(cur) = st.tracks.get(station)
        && cur.same(&t)
        && cur.at.is_some()
    {
        return;
    }
    st.version += 1;
    let list = st.history.entry(station.to_string()).or_default();
    list.retain(|x| !x.same(&t));
    list.insert(0, t.clone());
    list.truncate(HISTORY_MAX);
    st.tracks.insert(station.to_string(), t);
}

fn split_title(s: &str) -> Track {
    match s.find(" - ") {
        Some(i) if i > 0 => Track {
            artist: clean(&s[..i]),
            title: clean(&s[i + 3..]),
            at: None,
            id: None,
        },
        _ => Track {
            artist: String::new(),
            title: clean(s),
            at: None,
            id: None,
        },
    }
}

fn agent(per_read: Option<Duration>, body: Option<Duration>) -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_connect(Some(Duration::from_secs(10)))
        .timeout_recv_response(Some(Duration::from_secs(15)))
        .timeout_per_read(per_read)
        .timeout_recv_body(body)
        .build()
        .into()
}

fn set_online(meta: &Meta, on: bool) {
    let mut st = meta.lock_ok();
    if st.online != on {
        st.online = on;
        st.version += 1;
    }
}

fn apply_events(meta: &Meta, data: &str) {
    let Ok(items) = serde_json::from_str::<Vec<MetaEvent>>(data) else {
        return;
    };
    let mut st = meta.lock_ok();
    if !st.online {
        st.online = true;
        st.version += 1;
    }
    for it in items {
        if !known(&it.station) {
            continue;
        }
        let t = Track {
            title: clean(&it.title),
            artist: clean(&it.artist),
            at: it.at,
            id: it.track_id.map(|s| clean(&s)),
        };
        push_track(&mut st, &it.station, t);
    }
}

fn run_sse(agent: &ureq::Agent, meta: &Meta) -> anyhow::Result<()> {
    let resp = agent
        .get(META_URL)
        .header("User-Agent", UA)
        .header("Accept", "text/event-stream")
        .call()?;
    set_online(meta, true);
    read_events(&mut BufReader::new(resp.into_body().into_reader()), meta)
}

/// Parse an SSE byte stream until it ends, applying each event to `meta`.
fn read_events<R: BufRead>(reader: &mut R, meta: &Meta) -> anyhow::Result<()> {
    let mut line = String::new();
    // Per the SSE spec an event is one or more `data:` lines ended by a blank line.
    let mut data = String::new();
    loop {
        line.clear();
        // Bounded read: `lines()` would buffer an endless line until memory runs out.
        let n = reader.take(LINE_MAX).read_line(&mut line)?;
        if n == 0 {
            return Ok(()); // server closed the stream
        }
        if !line.ends_with('\n') && n as u64 == LINE_MAX {
            anyhow::bail!("SSE line too long");
        }
        let l = line.trim_end_matches(['\r', '\n']);
        if l.is_empty() {
            if !data.is_empty() {
                apply_events(meta, &data);
                data.clear();
            }
        } else if let Some(d) = l.strip_prefix("data:") {
            if data.len() + d.len() > LINE_MAX as usize {
                anyhow::bail!("SSE event too large");
            }
            if !data.is_empty() {
                data.push('\n');
            }
            data.push_str(d.strip_prefix(' ').unwrap_or(d));
        }
    }
}

fn fetch_status(agent: &ureq::Agent, meta: &Meta, seed: bool) -> anyhow::Result<()> {
    let json: serde_json::Value = agent
        .get(&status_url())
        .header("User-Agent", UA)
        .call()?
        .body_mut()
        .read_json()?;
    let one;
    let sources: &[serde_json::Value] = match &json["icestats"]["source"] {
        serde_json::Value::Array(a) => a,
        v @ serde_json::Value::Object(_) => {
            one = [v.clone()];
            &one
        }
        _ => &[],
    };
    let mut counts: HashMap<String, u32> = HashMap::new();
    let mut st = meta.lock_ok();
    st.version += 1;
    for src in sources {
        let url = src["listenurl"].as_str().unwrap_or("");
        let Some(file) = url.rsplit('/').next() else {
            continue;
        };
        let Some((id, ext)) = file.rsplit_once('.') else {
            continue;
        };
        if !known(id) || !matches!(ext, "mp3" | "ogg" | "m4a") {
            continue;
        }
        let n = u32::try_from(src["listeners"].as_u64().unwrap_or(0)).unwrap_or(u32::MAX);
        let c = counts.entry(id.into()).or_default();
        *c = c.saturating_add(n);
        if seed && ext == "mp3" {
            let mut list: Vec<Track> = src["playlist"]["trackList"]
                .as_array()
                .map(|a| {
                    a.iter()
                        .take(HISTORY_MAX * 4)
                        .map(|x| split_title(x["title"].as_str().unwrap_or("")))
                        .collect()
                })
                .unwrap_or_default();
            list.retain(|t| !t.title.is_empty());
            list.reverse();
            list.truncate(HISTORY_MAX);
            if !list.is_empty() && st.history.get(id).is_none_or(|h| h.is_empty()) {
                st.history.insert(id.into(), list);
            }
            let title = clean(src["title"].as_str().unwrap_or(""));
            let artist = clean(src["artist"].as_str().unwrap_or(""));
            if !st.tracks.contains_key(id) && (!title.is_empty() || !artist.is_empty()) {
                let t = if artist.is_empty() {
                    split_title(&title)
                } else {
                    Track {
                        artist,
                        title,
                        at: None,
                        id: None,
                    }
                };
                st.tracks.insert(id.into(), t);
            }
        }
    }
    st.listeners = counts;
    Ok(())
}

pub fn start() -> Meta {
    let meta: Meta = Arc::default();

    let m = meta.clone();
    thread::spawn(move || {
        // One agent per thread, so reconnects and polls reuse its connection pool.
        let agent = agent(Some(SSE_IDLE), None);
        let mut fails = 0u32;
        loop {
            let started = std::time::Instant::now();
            let _ = run_sse(&agent, &m);
            set_online(&m, false);
            // Back off when the feed keeps failing fast, instead of hammering it every 3 s.
            fails = if started.elapsed() > Duration::from_secs(60) {
                0
            } else {
                fails + 1
            };
            thread::sleep(Duration::from_secs((3u64 << fails.min(4)).min(60)));
        }
    });

    let m = meta.clone();
    thread::spawn(move || {
        let agent = agent(None, Some(Duration::from_secs(20)));
        let mut seeded = false;
        loop {
            seeded |= fetch_status(&agent, &m, !seeded).is_ok();
            thread::sleep(Duration::from_secs(if seeded { 60 } else { 10 }));
        }
    });

    meta
}

#[cfg(test)]
mod tests {
    use super::*;

    fn feed(input: &str) -> (MetaState, anyhow::Result<()>) {
        let meta: Meta = Arc::default();
        let res = read_events(&mut input.as_bytes(), &meta);
        let st = meta.lock_ok().clone();
        (st, res)
    }

    #[test]
    fn parses_events_and_ignores_unknown_stations() {
        let (st, res) = feed(
            "data: [{\"station\":\"nightride\",\"title\":\"T\",\"artist\":\"A\",\"at\":5}]\n\n\
             data: [{\"station\":\"nope\",\"title\":\"X\",\"artist\":\"Y\"}]\n\n",
        );
        assert!(res.is_ok());
        let t = &st.tracks["nightride"];
        assert_eq!(
            (t.title.as_str(), t.artist.as_str(), t.at),
            ("T", "A", Some(5))
        );
        assert!(!st.tracks.contains_key("nope"));
        assert!(st.online && st.version > 0);
    }

    #[test]
    fn joins_multiline_data_and_skips_bad_json() {
        let (st, _) = feed(
            "data: not json\n\n: comment\ndata: [{\"station\":\"ebsm\",\ndata: \"title\":\"T\"}]\r\n\r\n",
        );
        assert_eq!(st.tracks["ebsm"].title, "T");
    }

    #[test]
    fn rejects_endless_lines() {
        let long = format!("data: {}", "x".repeat(LINE_MAX as usize + 10));
        let (_, res) = feed(&long);
        assert!(res.is_err());
    }

    #[test]
    fn strips_control_and_bidi_characters_and_caps_length() {
        assert_eq!(
            clean(" a\x1b]52;c;evil\x07b\u{202e}c\u{9b} "),
            "a]52;c;evilbc"
        );
        assert_eq!(clean(&"x".repeat(1000)).len(), TEXT_MAX);
    }

    #[test]
    fn splits_artist_and_title() {
        let t = split_title("Artist - Song - Remix");
        assert_eq!(
            (t.artist.as_str(), t.title.as_str()),
            ("Artist", "Song - Remix")
        );
        let t = split_title(" - Song");
        assert_eq!((t.artist.as_str(), t.title.as_str()), ("", "- Song"));
    }

    #[test]
    fn history_dedupes_and_is_bounded() {
        let mut st = MetaState::default();
        for i in 0..40 {
            let t = Track {
                title: format!("t{}", i % 20),
                artist: "a".into(),
                at: Some(i),
                id: None,
            };
            push_track(&mut st, "nightride", t);
        }
        let h = &st.history["nightride"];
        assert_eq!(h.len(), HISTORY_MAX);
        assert_eq!(h[0].title, "t19");
    }
}
