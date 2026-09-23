import { cleanup, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { AuthContext } from '../auth/useAuth.js'

const setupToken = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG'
const anonymousSession = {
  user: null,
  isAuthenticated: false,
  isLoading: false,
  login: vi.fn(),
  register: vi.fn(),
  logout: vi.fn(),
}
const json = (body, status) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json' },
})

function renderSetup(token = setupToken) {
  const entry = token === null
    ? '/setup-password'
    : `/setup-password#token=${encodeURIComponent(token)}`
  window.history.replaceState({}, '', entry)
  return render(<MemoryRouter initialEntries={[entry]}><AuthContext.Provider value={anonymousSession}><App /></AuthContext.Provider></MemoryRouter>)
}

beforeEach(() => {
  sessionStorage.clear()
  localStorage.clear()
  vi.stubGlobal('fetch', vi.fn())
  vi.stubGlobal('matchMedia', vi.fn(() => ({
    matches: false,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
  })))
})
afterEach(() => {
  cleanup()
  sessionStorage.clear()
  localStorage.clear()
  window.history.replaceState({}, '', '/')
  vi.unstubAllGlobals()
})

describe('Technician password setup', () => {
  it('consumes the token from the fragment and clears it from browser history immediately', () => {
    renderSetup()

    expect(screen.getByRole('heading', { name: 'Set your password' })).toBeInTheDocument()
    expect(window.location.pathname).toBe('/setup-password')
    expect(window.location.hash).toBe('')
    expect(document.body).not.toHaveTextContent(setupToken)
    expect(JSON.stringify({ ...sessionStorage })).not.toContain(setupToken)
    expect(JSON.stringify({ ...localStorage })).not.toContain(setupToken)
  })

  it('submits the actual activation contract without authentication and routes to normal login', async () => {
    fetch.mockResolvedValue(new Response(null, { status: 204 }))
    renderSetup()
    await userEvent.type(screen.getByLabelText('Password', { exact: true }), 'Strong1!Password')
    await userEvent.type(screen.getByLabelText('Confirm password'), 'Strong1!Password')

    await userEvent.click(screen.getByRole('button', { name: 'Activate account' }))

    expect(await screen.findByRole('heading', { name: 'Sign in to RentFlow' })).toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('Technician account is active')
    const [url, options] = fetch.mock.calls[0]
    expect(new URL(url, 'http://localhost').pathname).toBe('/api/auth/maintenance-technicians/activate')
    expect(url).not.toContain(setupToken)
    expect(options.method).toBe('POST')
    expect(options.headers.Authorization).toBeUndefined()
    expect(JSON.parse(options.body)).toEqual({
      setupToken,
      password: 'Strong1!Password',
      passwordConfirmation: 'Strong1!Password',
    })
  })

  it('validates password policy and confirmation before sending the token', async () => {
    renderSetup()
    await userEvent.type(screen.getByLabelText('Password', { exact: true }), 'alllowercase')
    await userEvent.type(screen.getByLabelText('Confirm password'), 'different')
    await userEvent.click(screen.getByRole('button', { name: 'Activate account' }))

    expect(screen.getByRole('alert')).toHaveTextContent('uppercase letter')
    expect(fetch).not.toHaveBeenCalled()
  })

  it.each([
    [400, { detail: 'The password setup token is invalid, expired, or has already been used.' }, 'invalid, expired, or has already been used'],
    [429, {}, 'Too many password setup attempts'],
    [500, { detail: 'sensitive server trace' }, 'Password setup could not be completed'],
  ])('shows a safe activation error for status %s', async (status, body, message) => {
    fetch.mockResolvedValue(json(body, status))
    renderSetup()
    await userEvent.type(screen.getByLabelText('Password', { exact: true }), 'Strong1!Password')
    await userEvent.type(screen.getByLabelText('Confirm password'), 'Strong1!Password')
    await userEvent.click(screen.getByRole('button', { name: 'Activate account' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(message)
    expect(screen.getByRole('alert')).not.toHaveTextContent(setupToken)
    expect(screen.getByRole('alert')).not.toHaveTextContent('sensitive server trace')
    expect(screen.getByRole('button', { name: 'Activate account' })).toBeEnabled()
  })

  it('shows a safe state when no setup token is present', () => {
    renderSetup(null)

    expect(screen.getByRole('heading', { name: 'Setup link unavailable' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Activate account' })).not.toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Return to sign in' })).toHaveAttribute('href', '/login')
    expect(fetch).not.toHaveBeenCalled()
  })
})
