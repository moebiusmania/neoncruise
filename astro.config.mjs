// @ts-check
import { defineConfig } from 'astro/config';
import preact from '@astrojs/preact';

// Deployed to GitHub Pages as a project site, so everything lives under /neoncruise/.
export default defineConfig({
  site: 'https://moebiusmania.github.io',
  base: '/neoncruise',
  integrations: [preact()],
  vite: {
    css: {
      modules: { localsConvention: 'camelCaseOnly' },
    },
  },
});
