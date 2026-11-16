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
            .and_then(|s| serde_json::from_str::<Settings>(&s).ok())
            .unwrap_or_default()
            .sanitized()
    }

    /// The file is user-editable: keep values in range so nothing downstream has to care.
    fn sanitized(mut self) -> Settings {
        self.volume = if self.volume.is_finite() {
            self.volume.clamp(0.0, 1.0)
        } else {
            Settings::default().volume
        };
        self
    }

    /// Write via a temp file + rename, so a crash or full disk mid-write can't leave a
    /// truncated file behind (which would silently reset every setting on next launch).
    pub fn save(&self) {
        let Some(p) = path() else { return };
        if let Some(dir) = p.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let Ok(s) = serde_json::to_string_pretty(self) else {
            return;
        };
        let tmp = p.with_extension("json.tmp");
        if std::fs::write(&tmp, s).is_ok() && std::fs::rename(&tmp, &p).is_err() {
            let _ = std::fs::remove_file(&tmp);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitizes_out_of_range_volume_and_keeps_defaults_for_missing_keys() {
        let s: Settings = serde_json::from_str(r#"{"volume": 7.5, "hiss": true}"#).unwrap();
        let s = s.sanitized();
        assert_eq!(s.volume, 1.0);
        assert!(s.hiss && s.scan);
        assert_eq!(s.station, "nightride");
        let s = Settings {
            volume: f32::NAN,
            ..Settings::default()
        }
        .sanitized();
        assert_eq!(s.volume, Settings::default().volume);
    }
}
