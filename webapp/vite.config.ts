import react from '@vitejs/plugin-react'
import legacy from '@vitejs/plugin-legacy'
import { defineConfig } from 'vite'

// Dev-time proxy to the Flask backend (see CLAUDE.md — `aniworld -w` defaults to
// port 8080). Everything this SPA doesn't own itself gets forwarded: the JSON
// API and the session-cookie based OIDC redirect dance (device-approval itself
// is plain JSON under /api/webapp, already covered by the /api proxy).
const backend = process.env.VITE_BACKEND_URL || 'http://localhost:8080'

// Served same-origin at the site root in prod (see app.py's `index` route,
// the only web frontend now that /react was removed) — base must match so
// built asset URLs resolve correctly.
export default defineConfig({
  base: '/',
  plugins: [
    react(),
    // Built-in smart-TV browsers (Vewd/Opera TV, Tizen, WebOS) often ship a
    // Chromium/WebKit engine several years old and never get updated once
    // the TV ships — e.g. a "Vewd Browser, Copyright 2019" splash typically
    // means a Chromium ~69-79 base, well short of what Vite's default
    // `<script type="module">` output and esbuild's default transpile
    // target (ES2020+, optional chaining/nullish-coalescing included)
    // assume. This plugin emits a second, Babel+core-js-polyfilled
    // `nomodule` bundle targeted at the classic `targets` list below —
    // browsers that understand `type="module"` (i.e. anything remotely
    // recent) load the normal modern build unchanged; anything older
    // transparently falls back to the legacy one. `modernPolyfills: true`
    // also patches modern-build-only gaps (e.g. `Array.prototype.at`) so
    // the “modern” bundle itself doesn’t assume too much either.
    legacy({
      targets: ['chrome >= 58', 'safari >= 10', 'ios >= 10'],
      modernPolyfills: true,
    }),
  ],
  server: {
    proxy: {
      '/api': backend,
      '/oidc': backend,
      '/admin': backend,
    },
  },
})
