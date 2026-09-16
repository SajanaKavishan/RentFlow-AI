import { cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import { AuthProvider } from '../auth/AuthContext.jsx'

const tenant = {
  id: 'landing-user',
  fullName: 'Taylor Tenant',
  email: 'tenant@example.com',
  phoneNumber: '+94 77 123 4567',
  role: 'Tenant',
}

function apiWith(currentUser = null) {
  return {
    login: vi.fn(),
    register: vi.fn(),
    getCurrentUser: vi.fn().mockResolvedValue(currentUser),
  }
}

function renderApp(api = apiWith(), initialEntry = '/') {
  return render(<MemoryRouter initialEntries={[initialEntry]}><AuthProvider api={api}><App /></AuthProvider></MemoryRouter>)
}

afterEach(() => { cleanup(); tokenStorage.clearToken() })

describe('public landing experience', () => {
  it('renders the public landing page at the root route', () => {
    renderApp()
    expect(screen.getByRole('heading', { name: 'Find your perfect home, smarter.' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: 'Everything you need for the rental journey.' })).toBeInTheDocument()
    expect(screen.queryByRole('navigation', { name: 'Primary navigation' })).not.toBeInTheDocument()
  })

  it('navigates Get Started to the real registration page', async () => {
    renderApp()
    await userEvent.click(screen.getAllByRole('link', { name: 'Get Started' })[0])
    expect(await screen.findByRole('heading', { name: 'Create your RentFlow account' })).toBeInTheDocument()
  })

  it('navigates an unauthenticated Sign In request to login', async () => {
    renderApp()
    await userEvent.click(screen.getAllByRole('button', { name: 'Sign In' })[0])
    expect(await screen.findByRole('heading', { name: 'Sign in to RentFlow' })).toBeInTheDocument()
  })

  it('keeps landing visible during session restoration and enters the authenticated home only after Sign In', async () => {
    let finishRestore
    const restoredUser = new Promise((resolve) => { finishRestore = resolve })
    tokenStorage.setToken('stored-token')
    const api = apiWith()
    api.getCurrentUser.mockReturnValue(restoredUser)
    renderApp(api)

    expect(screen.getByRole('heading', { name: 'Find your perfect home, smarter.' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Welcome, Taylor Tenant' })).not.toBeInTheDocument()

    await userEvent.click(screen.getAllByRole('button', { name: 'Sign In' })[0])
    expect(screen.getAllByRole('button', { name: 'Restoring…' })[0]).toBeDisabled()
    finishRestore(tenant)

    expect(await screen.findByRole('heading', { name: 'Welcome, Taylor Tenant' })).toBeInTheDocument()
    expect(screen.getByRole('navigation', { name: 'Primary navigation' })).toBeInTheDocument()
  })

  it('uses in-page section links without leaving the landing route', async () => {
    renderApp()
    const navigation = screen.getByRole('navigation', { name: 'Landing page navigation' })
    const platformLink = within(navigation).getByRole('link', { name: 'Platform' })
    expect(platformLink).toHaveAttribute('href', '#platform')
    await userEvent.click(platformLink)
    expect(screen.getByRole('heading', { name: 'Everything you need for the rental journey.' })).toBeInTheDocument()
  })

  it('opens and closes the accessible mobile menu', async () => {
    renderApp()
    const openButton = screen.getByRole('button', { name: 'Open menu' })
    expect(openButton).toHaveAttribute('aria-expanded', 'false')
    await userEvent.click(openButton)
    expect(screen.getByRole('button', { name: 'Close menu' })).toHaveAttribute('aria-expanded', 'true')
    await userEvent.click(within(screen.getByRole('navigation', { name: 'Landing page navigation' })).getByRole('link', { name: 'Roles' }))
    expect(screen.getByRole('button', { name: 'Open menu' })).toHaveAttribute('aria-expanded', 'false')
  })
})
