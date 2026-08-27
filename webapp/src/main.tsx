import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import App from './App.tsx'
import { AuthProvider } from './context/AuthContext.tsx'
import { applyTvAttribute } from './tv/detectTv.ts'
import './styles/theme.css'
import './styles/global.css'

// Set before the first paint (not from a useEffect, which would run after
// React's initial commit) so a real TV browser never flashes non-TV sizing
// for a frame before GridPage's [data-tv]-scoped CSS takes effect.
applyTvAttribute()

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
})

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <App />
        </AuthProvider>
      </QueryClientProvider>
    </BrowserRouter>
  </StrictMode>,
)
