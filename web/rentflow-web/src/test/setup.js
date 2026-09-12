import '@testing-library/jest-dom/vitest'
import { afterEach, vi } from 'vitest'

afterEach(() => {
  sessionStorage.clear()
  vi.restoreAllMocks()
})
