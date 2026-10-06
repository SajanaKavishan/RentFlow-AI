const configuredBaseUrl = (import.meta.env.VITE_API_BASE_URL || '').trim()

// In deployed production builds, never fallback to localhost.
export const API_BASE_URL = (
  configuredBaseUrl || (import.meta.env.DEV || import.meta.env.MODE === 'test' ? 'http://localhost:5277' : '')
).replace(/\/+$/, '')
