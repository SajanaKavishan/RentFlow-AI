import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { ApiError, apiRequest, setUnauthorizedHandler } from '../../core/api/apiClient.js'
import { tokenStorage } from '../../core/auth/tokenStorage.js'
import { AuthProvider } from './AuthContext.jsx'
import { useAuth } from './useAuth.js'
import RegisterPage from './pages/RegisterPage.jsx'

const tenant = {
  id: '11111111-1111-1111-1111-111111111112',
  fullName: 'Taylor Tenant',
  email: 'tenant@example.com',
  phoneNumber: '+94 77 123 4567',
  role: 'Tenant',
}

function renderApp(api, initialEntry = '/login') {
  return render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <AuthProvider api={api}><App /></AuthProvider>
    </MemoryRouter>,
  )
}

describe('React authentication', () => {
  afterEach(() => { cleanup(); setUnauthorizedHandler(null) })

  it('persists and clears the access token through the storage abstraction', () => {
    tokenStorage.setToken('access-token')
    expect(tokenStorage.getToken()).toBe('access-token')
    tokenStorage.clearToken()
    expect(tokenStorage.getToken()).toBeNull()
  })

  it('logs in, persists the token, and loads the authoritative current user', async () => {
    const api = {
      login: vi.fn().mockResolvedValue({ accessToken: 'access-token', user: tenant }),
      register: vi.fn(),
      getCurrentUser: vi.fn().mockResolvedValue(tenant),
    }
    renderApp(api)
    await userEvent.type(await screen.findByLabelText('Email'), tenant.email)
    await userEvent.type(screen.getByLabelText('Password'), 'Password1!')
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    expect(await screen.findByText('Welcome, Taylor Tenant')).toBeInTheDocument()
    expect(tokenStorage.getToken()).toBe('access-token')
    expect(api.getCurrentUser).toHaveBeenCalled()
  })

  it('shows a safe login failure', async () => {
    const api = {
      login: vi.fn().mockRejectedValue(new ApiError('Email or password is incorrect.', 401)),
      register: vi.fn(),
      getCurrentUser: vi.fn(),
    }
    renderApp(api)
    await userEvent.type(await screen.findByLabelText('Email'), tenant.email)
    await userEvent.type(screen.getByLabelText('Password'), 'wrong-password')
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Email or password is incorrect.')
    expect(tokenStorage.getToken()).toBeNull()
  })

  it('toggles password visibility without changing the real login payload', async () => {
    const api = { login: vi.fn().mockResolvedValue({ accessToken: 'access-token', user: tenant }), register: vi.fn(), getCurrentUser: vi.fn().mockResolvedValue(tenant) }
    renderApp(api)
    const password = await screen.findByLabelText('Password')
    await userEvent.type(screen.getByLabelText('Email'), tenant.email)
    await userEvent.type(password, 'Password1!')
    await userEvent.click(screen.getByRole('button', { name: 'Show password' }))
    expect(password).toHaveAttribute('type', 'text')
    await userEvent.click(screen.getByRole('button', { name: 'Hide password' }))
    expect(password).toHaveAttribute('type', 'password')
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    expect(api.login).toHaveBeenCalledWith({ email: tenant.email, password: 'Password1!' })
  })

  it('restores a stored session from /me', async () => {
    tokenStorage.setToken('stored-token')
    const api = { login: vi.fn(), register: vi.fn(), getCurrentUser: vi.fn().mockResolvedValue(tenant) }
    function Probe() {
      const auth = useAuth()
      return <span>{auth.isLoading ? 'loading' : auth.user?.email ?? 'anonymous'}</span>
    }
    render(<AuthProvider api={api}><Probe /></AuthProvider>)
    expect(await screen.findByText(tenant.email)).toBeInTheDocument()
  })

  it('clears authentication once when an authenticated request returns 401', async () => {
    tokenStorage.setToken('expired-token')
    const handler = vi.fn()
    setUnauthorizedHandler(handler)
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('{}', {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    })))
    await expect(apiRequest('/api/private')).rejects.toMatchObject({ statusCode: 401 })
    expect(tokenStorage.getToken()).toBeNull()
    expect(handler).toHaveBeenCalledTimes(1)
  })

  it('routes an authenticated tenant away from landlord-only pages', async () => {
    tokenStorage.setToken('stored-token')
    const api = { login: vi.fn(), register: vi.fn(), getCurrentUser: vi.fn().mockResolvedValue(tenant) }
    renderApp(api, '/viewing-requests')
    expect(await screen.findByRole('heading', { name: 'Not accessible' })).toBeInTheDocument()
  })

  it('offers only Tenant and Landlord during public registration', async () => {
    const api = { login: vi.fn(), register: vi.fn(), getCurrentUser: vi.fn() }
    render(<MemoryRouter><AuthProvider api={api}><RegisterPage /></AuthProvider></MemoryRouter>)
    const select = await screen.findByLabelText('Account type')
    expect(Array.from(select.options).map((option) => option.value)).toEqual(['Tenant', 'Landlord'])
    expect(screen.queryByRole('option', { name: 'Admin' })).not.toBeInTheDocument()
    fireEvent.change(select, { target: { value: 'Landlord' } })
    expect(select).toHaveValue('Landlord')
  })

  it('registers with all real fields and only the selected public role', async () => {
    const api = { login: vi.fn(), register: vi.fn().mockResolvedValue({ accessToken: 'registered-token', user: tenant }), getCurrentUser: vi.fn().mockResolvedValue(tenant) }
    renderApp(api, '/register')
    await userEvent.type(await screen.findByLabelText('Full name'), 'Taylor Tenant')
    await userEvent.type(screen.getByLabelText('Email'), tenant.email)
    await userEvent.type(screen.getByLabelText('Phone number'), tenant.phoneNumber)
    await userEvent.type(screen.getByLabelText('Password', { exact: true }), 'Password1!')
    await userEvent.type(screen.getByLabelText('Confirm password'), 'Password1!')
    await userEvent.click(screen.getByRole('button', { name: 'Create account' }))
    expect(api.register).toHaveBeenCalledWith({ fullName: 'Taylor Tenant', email: tenant.email, phoneNumber: tenant.phoneNumber, password: 'Password1!', role: 'Tenant' })
    expect(await screen.findByRole('heading', { name: 'Welcome, Taylor Tenant' })).toBeInTheDocument()
  })
})
