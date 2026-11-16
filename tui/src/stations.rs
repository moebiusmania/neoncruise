pub struct Station {
    pub id: &'static str,
    pub name: &'static str,
    pub tag: &'static str,
    /// Base oklch hue for the station's colour world.
    pub hue: f32,
}

pub const STATIONS: [Station; 7] = [
    Station {
        id: "nightride",
        name: "NIGHTRIDE",
        tag: "Synthwave · Retrowave · Outrun",
        hue: 350.0,
    },
    Station {
        id: "chillsynth",
        name: "CHILLSYNTH",
        tag: "Chillsynth · Chillwave · Instrumental",
        hue: 195.0,
    },
    Station {
        id: "datawave",
        name: "DATAWAVE",
        tag: "Glitchy Synthwave · IDM · Retro Computing",
        hue: 150.0,
    },
    Station {
        id: "spacesynth",
        name: "SPACESYNTH",
        tag: "Spacesynth · Space Disco · Vocoder Italo",
        hue: 255.0,
    },
    Station {
        id: "darksynth",
        name: "DARKSYNTH",
        tag: "Darksynth · Cyberpunk · Synthmetal",
        hue: 25.0,
    },
    Station {
        id: "horrorsynth",
        name: "HORRORSYNTH",
        tag: "Horrorsynth · Witch House",
        hue: 305.0,
    },
    Station {
        id: "ebsm",
        name: "EBSM",
        tag: "EBSM · Industrial · Clubbing",
        hue: 75.0,
    },
];

pub const STREAM_HOST: &str = "https://stream.nightride.fm";
pub const META_URL: &str = "https://nightride.fm/meta";

pub fn stream_url(id: &str) -> String {
    format!("{STREAM_HOST}/{id}.mp3")
}

pub fn status_url() -> String {
    format!("{STREAM_HOST}/status-json.xsl")
}

pub fn total() -> String {
    format!("{:02}", STATIONS.len())
}

pub fn tape_num(i: usize) -> String {
    format!("{:02}", i + 1)
}

pub fn tape_code(i: usize) -> String {
    format!("NRF-0{}", i + 1)
}

pub fn wrap_index(i: isize) -> usize {
    let n = STATIONS.len() as isize;
    (((i % n) + n) % n) as usize
}

pub fn index_of(id: &str) -> Option<usize> {
    STATIONS.iter().position(|s| s.id == id)
}
