// @ts-check
import { defineConfig, fontProviders } from 'astro/config';
import preact from '@astrojs/preact';

const STREAM = 'https://stream.nightride.fm';
const META = 'https://nightride.fm';

// Deployed to GitHub Pages as a project site, so everything lives under /neoncruise/.
export default defineConfig({
  site: 'https://moebiusmania.github.io',
  base: '/neoncruise',
  integrations: [preact()],

  // Fonts are downloaded at build time and served from our own origin: no render-blocking
  // third-party CSS, no extra DNS/TLS handshakes, and no visitor IPs sent to Google.
  fonts: [
    {
      provider: fontProviders.google(),
      name: 'Syncopate',
      cssVariable: '--font-syncopate',
      weights: [400, 700],
      subsets: ['latin'],
      fallbacks: ['Arial Black', 'sans-serif'],
    },
    {
      provider: fontProviders.google(),
      name: 'VT323',
      cssVariable: '--font-vt323',
      weights: [400],
      subsets: ['latin'],
      fallbacks: ['ui-monospace', 'Menlo', 'monospace'],
    },
    {
      provider: fontProviders.google(),
      name: 'Space Grotesk',
      cssVariable: '--font-space-grotesk',
      weights: [400, 500, 600],
      subsets: ['latin'],
      fallbacks: ['system-ui', 'sans-serif'],
    },
  ],

  // Emits a hashed <meta http-equiv="content-security-policy"> (GitHub Pages can't set headers).
  security: {
    csp: {
      directives: [
        "default-src 'self'",
        `connect-src 'self' ${META} ${STREAM}`,
        `media-src ${STREAM}`,
        "img-src 'self' data:",
        "font-src 'self'",
        "manifest-src 'self'",
        "worker-src 'self'",
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'none'",
      ],
    },
  },

  // No Markdown here; Shiki's inline styles would also conflict with the CSP.
  markdown: { syntaxHighlight: false },

  vite: {
    css: {
      modules: { localsConvention: 'camelCaseOnly' },
    },
  },
});
