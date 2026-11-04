// Renders the app icon SVG into the PNG sizes the PWA manifest and iOS need.
import { Resvg } from '@resvg/resvg-js';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';

const out = 'public/icons';
mkdirSync(out, { recursive: true });
const svg = readFileSync(`${out}/icon.svg`, 'utf8');

// Maskable variant: full-bleed background, artwork shrunk into the 80% safe zone.
const maskable = svg
  .replace('<rect width="512" height="512" rx="112"', '<rect width="512" height="512"')
  .replace('<g id="art">', '<g id="art" transform="translate(51.2 51.2) scale(0.8)">');

const render = (src: string, size: number, file: string) => {
  const png = new Resvg(src, { fitTo: { mode: 'width', value: size } }).render().asPng();
  writeFileSync(`${out}/${file}`, png);
  console.log('wrote', file);
};

render(svg, 192, 'icon-192.png');
render(svg, 512, 'icon-512.png');
render(maskable, 512, 'maskable-512.png');
render(maskable, 180, 'apple-touch-icon.png');
