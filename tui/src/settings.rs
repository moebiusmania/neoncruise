use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    pub station: String,
    pub volume: f32,
    pub scan: bool,
    pub flicker: bool,
    pub noise: bool,
    /// Drive the grid and spectrum from the real audio instead of a simulated beat.
    pub reactive: bool,
    /// Mix a faint analog tape hiss over the stream.
    pub hiss: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            station: "nightride".into(),
            volume: 0.85,
            scan: true,
            flicker: true,
            noise: true,
            reactive: true,
            hiss: false,
        }
    }
}

fn path() -> Option<PathBuf> {
    Some(dirs::config_dir()?.join("neoncruise").join("settings.json"))
}

impl Settings {
    pub fn load() -> Settings {
        path()
            .and_then(|p| std::fs::read_to_string(p).ok())
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }

    pub fn save(&self) {
        let Some(p) = path() else { return };
        if let Some(dir) = p.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        if let Ok(s) = serde_json::to_string_pretty(self) {
            let _ = std::fs::write(p, s);
        }
    }
}
