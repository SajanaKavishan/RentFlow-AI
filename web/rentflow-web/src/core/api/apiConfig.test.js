import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

describe('apiConfig API_BASE_URL', () => {
  beforeEach(() => {
    vi.resetModules()
  })

  afterEach(() => {
    vi.unstubAllEnvs()
  })

  it('uses configured VITE_API_BASE_URL and trims trailing slashes', async () => {
    vi.stubEnv('VITE_API_BASE_URL', 'https://rentflow-api.azurewebsites.net///')
    const { API_BASE_URL } = await import('./apiConfig.js')
    expect(API_BASE_URL).toBe('https://rentflow-api.azurewebsites.net')
  })

  it('falls back to localhost in test/development mode when VITE_API_BASE_URL is absent', async () => {
    vi.stubEnv('VITE_API_BASE_URL', '')
    const { API_BASE_URL } = await import('./apiConfig.js')
    expect(API_BASE_URL).toBe('http://localhost:5277')
  })
})
