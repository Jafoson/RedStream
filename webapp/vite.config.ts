import react from '@vitejs/plugin-react'
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
  plugins: [react()],
  server: {
    proxy: {
      '/api': backend,
      '/oidc': backend,
      '/admin': backend,
    },
  },
})
