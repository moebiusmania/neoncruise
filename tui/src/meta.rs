//! Now-playing metadata: the Nightride FM SSE feed plus the Icecast status JSON.

use crate::stations::{META_URL, STATIONS, status_url};
use serde::Deserialize;
use std::collections::HashMap;
use std::io::{BufRead, BufReader};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

const HISTORY_MAX: usize = 15;
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

#[derive(Default)]
pub struct MetaState {
    pub tracks: HashMap<String, Track>,
    pub history: HashMap<String, Vec<Track>>,
    pub listeners: HashMap<String, u32>,
    pub online: bool,
}

pub type Meta = Arc<Mutex<MetaState>>;

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
    let list = st.history.entry(station.to_string()).or_default();
    list.retain(|x| !x.same(&t));
    list.insert(0, t.clone());
    list.truncate(HISTORY_MAX);
    st.tracks.insert(station.to_string(), t);
}

fn split_title(s: &str) -> Track {
    match s.find(" - ") {
        Some(i) if i > 0 => Track {
            artist: s[..i].trim().into(),
            title: s[i + 3..].trim().into(),
            at: None,
            id: None,
        },
        _ => Track {
            artist: String::new(),
            title: s.trim().into(),
            at: None,
            id: None,
        },
    }
}

fn agent(read_timeout: Option<Duration>) -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_connect(Some(Duration::from_secs(10)))
        .timeout_recv_response(Some(Duration::from_secs(15)))
        .timeout_recv_body(read_timeout)
        .build()
        .into()
}

fn run_sse(meta: &Meta) -> anyhow::Result<()> {
    let resp = agent(None)
        .get(META_URL)
        .header("User-Agent", UA)
        .header("Accept", "text/event-stream")
        .call()?;
    meta.lock().unwrap().online = true;
    let reader = BufReader::new(resp.into_body().into_reader());
    for line in reader.lines() {
        let line = line?;
        let Some(data) = line.strip_prefix("data:") else {
            continue;
        };
        let Ok(items) = serde_json::from_str::<Vec<MetaEvent>>(data.trim()) else {
            continue;
        };
        let mut st = meta.lock().unwrap();
        st.online = true;
        for it in items {
            if !known(&it.station) {
                continue;
            }
            let t = Track {
                title: it.title,
                artist: it.artist,
                at: it.at,
                id: it.track_id,
            };
            push_track(&mut st, &it.station, t);
        }
    }
    Ok(())
}

fn fetch_status(meta: &Meta, seed: bool) -> anyhow::Result<()> {
    let json: serde_json::Value = agent(Some(Duration::from_secs(20)))
        .get(&status_url())
        .header("User-Agent", UA)
        .call()?
        .body_mut()
        .read_json()?;
    let sources = match &json["icestats"]["source"] {
        serde_json::Value::Array(a) => a.clone(),
        v @ serde_json::Value::Object(_) => vec![v.clone()],
        _ => vec![],
    };
    let mut counts: HashMap<String, u32> = HashMap::new();
    let mut st = meta.lock().unwrap();
    for src in &sources {
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
        let n = src["listeners"].as_u64().unwrap_or(0) as u32;
        *counts.entry(id.into()).or_default() += n;
        if seed && ext == "mp3" {
            let mut list: Vec<Track> = src["playlist"]["trackList"]
                .as_array()
                .map(|a| {
                    a.iter()
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
            let title = src["title"].as_str().unwrap_or("");
            let artist = src["artist"].as_str().unwrap_or("");
            if !st.tracks.contains_key(id) && (!title.is_empty() || !artist.is_empty()) {
                let t = if artist.is_empty() {
                    split_title(title)
                } else {
                    Track {
                        artist: artist.into(),
                        title: title.into(),
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
        loop {
            let _ = run_sse(&m);
            m.lock().unwrap().online = false;
            thread::sleep(Duration::from_secs(3));
        }
    });

    let m = meta.clone();
    thread::spawn(move || {
        let mut seeded = false;
        loop {
            seeded |= fetch_status(&m, !seeded).is_ok();
            thread::sleep(Duration::from_secs(if seeded { 60 } else { 10 }));
        }
    });

    meta
}
