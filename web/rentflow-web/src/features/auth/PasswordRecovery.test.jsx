import { cleanup, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import { AuthContext } from './useAuth.js'

const resetToken = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG'
const genericMessage = 'If an account matches that email, password reset instructions will be sent.'
const anonymousSession = {
  user: null,
  isAuthenticated: false,
  isLoading: false,
  login: vi.fn(),
  register: vi.fn(),
  logout: vi.fn(),
}
const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json' },
})

function renderRoute(entry) {
  window.history.replaceState({}, '', entry)
  return render(<MemoryRouter initialEntries={[entry]}><AuthContext.Provider value={anonymousSession}><App /></AuthContext.Provider></MemoryRouter>)
}

function renderReset(token = resetToken) {
  return renderRoute(token === null
    ? '/reset-password'
    : `/reset-password#token=${encodeURIComponent(token)}`)
}

async function enterValidResetPassword() {
  await userEvent.type(screen.getByLabelText('New password'), 'Replacement2@Password')
  await userEvent.type(screen.getByLabelText('Confirm new password'), 'Replacement2@Password')
}

beforeEach(() => {
  tokenStorage.clearToken()
  anonymousSession.login.mockClear()
  vi.stubGlobal('fetch', vi.fn())
  vi.stubGlobal('matchMedia', vi.fn(() => ({
    matches: false,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
  })))
})

afterEach(() => {
  cleanup()
  tokenStorage.clearToken()
  window.history.replaceState({}, '', '/')
  vi.unstubAllGlobals()
})

describe('password recovery', () => {
  it('links from Login to the Forgot Password page', async () => {
    renderRoute('/login')

    const link = screen.getByRole('link', { name: 'Forgot password?' })
    expect(link).toHaveAttribute('href', '/forgot-password')
    await userEvent.click(link)

    expect(screen.getByRole('heading', { name: 'Forgot password' })).toBeInTheDocument()
  })

  it('validates email locally and shows the generic confirmed response', async () => {
    fetch.mockResolvedValueOnce(json({
      message: genericMessage,
      developmentResetLink: `http://localhost:5173/reset-password#token=${resetToken}`,
    }))
    renderRoute('/forgot-password')

    await userEvent.type(screen.getByLabelText('Email'), 'invalid')
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    expect(screen.getByRole('alert')).toHaveTextContent('Enter a valid email address.')
    expect(fetch).not.toHaveBeenCalled()

    await userEvent.clear(screen.getByLabelText('Email'))
    await userEvent.type(screen.getByLabelText('Email'), 'user@example.com')
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))

    expect(await screen.findByRole('heading', { name: 'Request confirmed' })).toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent(genericMessage)
    expect(screen.getByRole('link', { name: 'Open the local reset page' })).toHaveAttribute(
      'href',
      `http://localhost:5173/reset-password#token=${resetToken}`,
    )
    const [url, options] = fetch.mock.calls[0]
    expect(new URL(url, 'http://localhost').pathname).toBe('/api/auth/forgot-password')
    expect(options.headers.Authorization).toBeUndefined()
    expect(JSON.parse(options.body)).toEqual({ email: 'user@example.com' })
  })

  it('consumes the reset token from the fragment and removes it from browser history', () => {
    renderReset()

    expect(screen.getByRole('heading', { name: 'Reset password' })).toBeInTheDocument()
    expect(window.location.pathname).toBe('/reset-password')
    expect(window.location.hash).toBe('')
    expect(document.body).not.toHaveTextContent(resetToken)
    expect(JSON.stringify({ ...sessionStorage })).not.toContain(resetToken)
    expect(JSON.stringify({ ...localStorage })).not.toContain(resetToken)
  })

  it('validates password policy and confirmation before submitting the token', async () => {
    renderReset()
    await userEvent.type(screen.getByLabelText('New password'), 'alllowercase')
    await userEvent.type(screen.getByLabelText('Confirm new password'), 'different')
    await userEvent.click(screen.getByRole('button', { name: 'Reset password' }))

    expect(screen.getByRole('alert')).toHaveTextContent('uppercase letter')
    expect(fetch).not.toHaveBeenCalled()

    await userEvent.clear(screen.getByLabelText('New password'))
    await userEvent.clear(screen.getByLabelText('Confirm new password'))
    await userEvent.type(screen.getByLabelText('New password'), 'Replacement2@Password')
    await userEvent.type(screen.getByLabelText('Confirm new password'), 'Different3#Password')
    await userEvent.click(screen.getByRole('button', { name: 'Reset password' }))
    expect(screen.getByRole('alert')).toHaveTextContent('Passwords do not match')
    expect(fetch).not.toHaveBeenCalled()
  })

  it.each([
    [400, { detail: 'The password reset token is invalid, expired, or has already been used.' }, 'invalid, expired, or has already been used'],
    [429, {}, 'Too many password reset attempts'],
    [500, { detail: 'secret reset-token server trace' }, 'Password reset could not be completed'],
  ])('shows a safe reset error for status %s', async (status, body, expectedMessage) => {
    fetch.mockResolvedValueOnce(json(body, status))
    renderReset()
    await enterValidResetPassword()
    await userEvent.click(screen.getByRole('button', { name: 'Reset password' }))

    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent(expectedMessage)
    expect(alert).not.toHaveTextContent(resetToken)
    expect(alert).not.toHaveTextContent('secret reset-token server trace')
    expect(screen.getByRole('button', { name: 'Reset password' })).toBeEnabled()
  })

  it('resets anonymously, clears the reset token and redirects to normal Login', async () => {
    fetch.mockResolvedValueOnce(json({ message: 'Your password was reset successfully.' }))
    renderReset()
    await enterValidResetPassword()

    await userEvent.click(screen.getByRole('button', { name: 'Reset password' }))

    expect(await screen.findByRole('heading', { name: 'Sign in to RentFlow' })).toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('password was reset successfully')
    expect(anonymousSession.login).not.toHaveBeenCalled()
    expect(tokenStorage.getToken()).toBeNull()
    const [url, options] = fetch.mock.calls[0]
    expect(new URL(url, 'http://localhost').pathname).toBe('/api/auth/reset-password')
    expect(url).not.toContain(resetToken)
    expect(options.headers.Authorization).toBeUndefined()
    expect(JSON.parse(options.body)).toEqual({
      token: resetToken,
      newPassword: 'Replacement2@Password',
      newPasswordConfirmation: 'Replacement2@Password',
    })
  })

  it('shows a safe state when the reset token is missing', () => {
    renderReset(null)

    expect(screen.getByRole('heading', { name: 'Reset link unavailable' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Request another link' })).toHaveAttribute('href', '/forgot-password')
    expect(screen.queryByRole('button', { name: 'Reset password' })).not.toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
  })
})
