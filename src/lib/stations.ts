export interface Station {
  id: string;
  name: string;
  tag: string;
  /** Base oklch hue for the station's colour world. */
  hue: number;
}

export const STATIONS: Station[] = [
  { id: 'nightride', name: 'NIGHTRIDE', tag: 'Synthwave · Retrowave · Outrun', hue: 350 },
  { id: 'chillsynth', name: 'CHILLSYNTH', tag: 'Chillsynth · Chillwave · Instrumental', hue: 195 },
  { id: 'datawave', name: 'DATAWAVE', tag: 'Glitchy Synthwave · IDM · Retro Computing', hue: 150 },
  { id: 'spacesynth', name: 'SPACESYNTH', tag: 'Spacesynth · Space Disco · Vocoder Italo', hue: 255 },
  { id: 'darksynth', name: 'DARKSYNTH', tag: 'Darksynth · Cyberpunk · Synthmetal', hue: 25 },
  { id: 'horrorsynth', name: 'HORRORSYNTH', tag: 'Horrorsynth · Witch House', hue: 305 },
  { id: 'ebsm', name: 'EBSM', tag: 'EBSM · Industrial · Clubbing', hue: 75 },
];

export const TOTAL = String(STATIONS.length).padStart(2, '0');

export const STREAM_HOST = 'https://stream.nightride.fm';
export const META_URL = 'https://nightride.fm/meta';
export const STATUS_URL = `${STREAM_HOST}/status-json.xsl`;

export const streamUrl = (id: string) => `${STREAM_HOST}/${id}.mp3`;

export const tapeNum = (i: number) => String(i + 1).padStart(2, '0');
export const tapeCode = (i: number) => `NRF-0${i + 1}`;

export const wrapIndex = (i: number) => ((i % STATIONS.length) + STATIONS.length) % STATIONS.length;
