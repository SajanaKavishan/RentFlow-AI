import { cleanup, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from '../../App.jsx'
import { AuthContext } from '../../features/auth/useAuth.js'
import { tokenStorage } from '../../core/auth/tokenStorage.js'

vi.mock('../../features/notifications/notificationsApi.js', async (importOriginal) => ({
  ...(await importOriginal()), getUnreadCount: vi.fn().mockResolvedValue(0),
}))

const setupToken = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG'
const account = (role = 'Admin') => ({
  id: '11111111-1111-1111-1111-111111111111', fullName: 'Sam Perera',
  email: 'sam@example.com', phoneNumber: '+94 77 123 4567', role,
})
const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json' },
})

function renderRoute(role = 'Admin', initialEntry = '/modules/users') {
  const session = { user: account(role), isAuthenticated: true, isLoading: false, logout: vi.fn() }
  return render(<MemoryRouter initialEntries={[initialEntry]}><AuthContext.Provider value={session}><App /></AuthContext.Provider></MemoryRouter>)
}

async function openForm() {
  await userEvent.click(screen.getByRole('button', { name: 'Add Technician' }))
}

async function fillForm() {
  if (!screen.queryByLabelText('Full name')) await openForm()
  await userEvent.type(screen.getByLabelText('Full name'), 'Taylor Technician')
  await userEvent.type(screen.getByLabelText('Email'), 'tech@example.com')
  await userEvent.type(screen.getByLabelText('Phone number'), '+94770000001')
}

beforeEach(() => {
  localStorage.clear()
  sessionStorage.clear()
  tokenStorage.setToken('admin-token')
  vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })))
  vi.stubGlobal('fetch', vi.fn())
  Object.defineProperty(navigator, 'clipboard', {
    configurable: true,
    value: { writeText: vi.fn().mockResolvedValue(undefined) },
  })
})
afterEach(() => {
  cleanup()
  tokenStorage.clearToken()
  localStorage.clear()
  sessionStorage.clear()
  vi.restoreAllMocks()
  vi.unstubAllGlobals()
  delete navigator.clipboard
})

describe('Admin Users page', () => {
  it('keeps the real directory limitation primary without invented data or controls', () => {
    renderRoute()
    const main = screen.getByRole('main')
    expect(within(main).getByRole('heading', { name: 'Users', level: 1 })).toBeInTheDocument()
    const addButton = within(main).getByRole('button', { name: 'Add Technician' })
    expect(addButton).toHaveAttribute('aria-expanded', 'false')
    expect(screen.queryByRole('dialog', { name: 'Add Technician' })).not.toBeInTheDocument()

    const directory = within(main).getByRole('region', { name: 'User directory' })
    expect(directory).toHaveTextContent('Integration pending')
    expect(directory).toHaveTextContent('does not currently expose an Admin-authorized endpoint')
    expect(directory).toHaveTextContent('No user records, totals, roles, joined dates, account statuses, search controls, or account-changing actions')
    expect(within(main).queryByRole('searchbox')).not.toBeInTheDocument()
    expect(within(main).queryByRole('table')).not.toBeInTheDocument()
    expect(main).not.toHaveTextContent(/8 total|7 active|deactivate|edit role|delete user/i)
    expect(fetch).not.toHaveBeenCalled()
  })

  it('reveals the existing provisioning form and moves focus to its first field', async () => {
    renderRoute()
    const addButton = screen.getByRole('button', { name: 'Add Technician' })
    await userEvent.click(addButton)

    expect(addButton).toHaveAttribute('aria-expanded', 'true')
    expect(screen.getByRole('dialog', { name: 'Add Technician' })).toHaveAttribute('aria-modal', 'true')
    expect(screen.getByLabelText('Full name')).toHaveFocus()
    expect(document.body.style.overflow).toBe('hidden')
    expect(screen.getByLabelText('Email')).toHaveAttribute('type', 'email')
    expect(screen.getByLabelText('Phone number')).toHaveAttribute('type', 'tel')
  })

  it('traps keyboard focus and closes an empty popup with Escape', async () => {
    renderRoute()
    await openForm()
    const submit = screen.getByRole('button', { name: 'Create pending Technician' })
    submit.focus()

    await userEvent.tab()
    expect(screen.getByRole('button', { name: 'Close Add Technician panel' })).toHaveFocus()
    await userEvent.keyboard('{Escape}')

    expect(screen.queryByRole('dialog', { name: 'Add Technician' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add Technician' })).toHaveFocus()
    expect(document.body.style.overflow).toBe('')
  })

  it('opens and focuses the provisioning form from the Admin dashboard action URL', () => {
    renderRoute('Admin', '/modules/users?action=add-technician')

    expect(screen.getByRole('button', { name: 'Add Technician' })).toHaveAttribute('aria-expanded', 'true')
    expect(screen.getByRole('dialog', { name: 'Add Technician' })).toHaveAttribute('aria-modal', 'true')
    expect(screen.getByLabelText('Full name')).toHaveFocus()
  })

  it('confirms before discarding an unsent form and restores trigger focus after closing', async () => {
    vi.spyOn(window, 'confirm').mockReturnValueOnce(false).mockReturnValueOnce(true)
    renderRoute()
    await openForm()
    await userEvent.type(screen.getByLabelText('Full name'), 'Taylor')

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }))
    expect(window.confirm).toHaveBeenCalledWith('Discard the unsent Technician details?')
    expect(screen.getByLabelText('Full name')).toHaveValue('Taylor')

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }))
    expect(screen.queryByRole('dialog', { name: 'Add Technician' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Add Technician' })).toHaveFocus()
  })

  it('submits the backend contract and displays a copyable one-time setup link', async () => {
    fetch.mockResolvedValue(json({
      id: '22222222-2222-2222-2222-222222222222',
      fullName: 'Taylor Technician',
      email: 'tech@example.com',
      phoneNumber: '+94770000001',
      role: 'MaintenanceTechnician',
      isActive: false,
      passwordSetupToken: setupToken,
      passwordSetupExpiresAt: '2026-09-23T16:00:00Z',
    }, 201))
    renderRoute()
    await fillForm()

    await userEvent.click(screen.getByRole('button', { name: 'Create pending Technician' }))

    const successHeading = await screen.findByRole('heading', { name: 'Securely deliver the setup link' })
    expect(successHeading).toHaveFocus()
    const [url, options] = fetch.mock.calls[0]
    expect(new URL(url, 'http://localhost').pathname).toBe('/api/admin/maintenance-technicians')
    expect(options.method).toBe('POST')
    expect(options.headers.Authorization).toBe('Bearer admin-token')
    expect(JSON.parse(options.body)).toEqual({
      fullName: 'Taylor Technician',
      email: 'tech@example.com',
      phoneNumber: '+94770000001',
    })
    const setupLink = screen.getByLabelText('One-time password-setup link')
    expect(setupLink.value).toContain(`/setup-password#token=${setupToken}`)
    expect(screen.getByText(/account is inactive/i)).toBeInTheDocument()
    expect(screen.getByText(/No email has been sent/i)).toBeInTheDocument()
    expect(JSON.stringify({ ...sessionStorage })).not.toContain(setupToken)
    expect(JSON.stringify({ ...localStorage })).not.toContain(setupToken)

    await userEvent.click(screen.getByRole('button', { name: 'Copy link' }))
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(setupLink.value)
    expect(await screen.findByText(/Setup link copied/)).toHaveAttribute('role', 'status')

    const confirmClose = vi.spyOn(window, 'confirm').mockReturnValue(false)
    await userEvent.click(screen.getByRole('button', { name: 'Close Add Technician panel' }))
    expect(confirmClose).toHaveBeenCalledWith(expect.stringContaining('clear the one-time setup link'))
    expect(screen.getByLabelText('One-time password-setup link')).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Clear setup link' }))
    expect(screen.queryByLabelText('One-time password-setup link')).not.toBeInTheDocument()
    expect(screen.getByLabelText('Full name')).toHaveFocus()
  })

  it('shows client validation and duplicate-email API errors', async () => {
    renderRoute()
    await openForm()
    await userEvent.click(screen.getByRole('button', { name: 'Create pending Technician' }))
    expect(screen.getByRole('alert')).toHaveTextContent('full name')
    expect(fetch).not.toHaveBeenCalled()

    await fillForm()
    fetch.mockResolvedValue(json({ detail: 'An account with this email already exists.' }, 409))
    await userEvent.click(screen.getByRole('button', { name: 'Create pending Technician' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('An account with this email already exists.')
  })

  it.each([
    [401, 'Your Admin session is no longer valid'],
    [403, 'not authorized to add Technicians'],
    [500, 'pending Technician account could not be created'],
  ])('shows a safe API error for status %s', async (status, message) => {
    fetch.mockResolvedValue(json({ detail: status === 500 ? 'server trace' : 'Denied' }, status))
    renderRoute()
    await fillForm()
    await userEvent.click(screen.getByRole('button', { name: 'Create pending Technician' }))
    expect(await screen.findByRole('alert')).toHaveTextContent(message)
    expect(screen.getByRole('alert')).not.toHaveTextContent('server trace')
  })

  it('shows and disables the loading state while creation is pending', async () => {
    let resolveRequest
    fetch.mockReturnValue(new Promise((resolve) => { resolveRequest = resolve }))
    renderRoute()
    await fillForm()
    await userEvent.click(screen.getByRole('button', { name: 'Create pending Technician' }))
    expect(screen.getByRole('button', { name: 'Creating pending account...' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Cancel' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Close Add Technician panel' })).toBeDisabled()
    resolveRequest(json({
      id: '22222222-2222-2222-2222-222222222222', fullName: 'Taylor Technician',
      email: 'tech@example.com', phoneNumber: '+94770000001', role: 'MaintenanceTechnician',
      isActive: false, passwordSetupToken: setupToken,
      passwordSetupExpiresAt: '2026-09-23T16:00:00Z',
    }, 201))
    expect(await screen.findByRole('heading', { name: 'Securely deliver the setup link' })).toBeInTheDocument()
  })

  it('keeps Users active and preserves shared navigation and account actions', () => {
    renderRoute()
    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    const usersLink = within(nav).getByRole('link', { name: 'Users' })
    expect(usersLink).toHaveAttribute('href', '/modules/users')
    expect(usersLink).toHaveAttribute('aria-current', 'page')
    expect(usersLink).not.toHaveTextContent('Soon')
    expect(screen.getByRole('link', { name: 'Notifications' })).toHaveAttribute('href', '/notifications')
    expect(within(nav).getByRole('link', { name: 'Profile' })).toHaveAttribute('href', '/profile')
    expect(within(nav).getByRole('button', { name: 'Logout' })).toBeInTheDocument()
  })

  it.each(['Tenant', 'Landlord', 'MaintenanceTechnician'])('blocks %s from the Admin Users route', (role) => {
    renderRoute(role)
    expect(screen.getByRole('heading', { name: 'Not accessible' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Add Technician' })).not.toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
  })
})
