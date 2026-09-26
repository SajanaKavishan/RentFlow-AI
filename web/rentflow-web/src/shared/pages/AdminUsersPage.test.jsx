import { cleanup, render, screen, waitFor, within } from '@testing-library/react'
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
const adminUser = {
  id: '11111111-1111-4111-8111-111111111111',
  fullName: 'Sam Perera',
  email: 'sam@example.com',
  role: 'Admin',
  isActive: true,
  createdAt: '2026-09-20T09:30:00Z',
}
const tenantUser = {
  id: '22222222-2222-4222-8222-222222222222',
  fullName: 'Nimali Tenant',
  email: 'nimali@example.com',
  role: 'Tenant',
  isActive: false,
  createdAt: '2026-09-18T12:00:00Z',
}
const provisionedUser = {
  id: '33333333-3333-4333-8333-333333333333',
  fullName: 'Taylor Technician',
  email: 'tech@example.com',
  role: 'MaintenanceTechnician',
  isActive: false,
  createdAt: '2026-09-24T08:00:00Z',
}
const provisionResponse = {
  ...provisionedUser,
  phoneNumber: '+94770000001',
  passwordSetupToken: setupToken,
  passwordSetupExpiresAt: '2026-09-24T16:00:00Z',
}
const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json' },
})

function directoryPage(items = [adminUser, tenantUser], overrides = {}) {
  const page = overrides.page ?? 1
  const pageSize = overrides.pageSize ?? 8
  const totalCount = overrides.totalCount ?? items.length
  const totalPages = Math.ceil(totalCount / pageSize)
  return {
    items,
    pagination: {
      page,
      pageSize,
      totalCount,
      totalPages,
      hasNextPage: page < totalPages,
      hasPreviousPage: page > 1 && totalPages > 0,
    },
  }
}

function installApi({ directory, provision = json(provisionResponse, 201) } = {}) {
  fetch.mockImplementation((input, options = {}) => {
    const url = new URL(input, 'http://localhost')
    if (url.pathname === '/api/admin/users') {
      if (directory) return typeof directory === 'function' ? directory(url, options) : directory
      const page = Number(url.searchParams.get('page'))
      const pageSize = Number(url.searchParams.get('pageSize'))
      return Promise.resolve(json(directoryPage([adminUser, tenantUser], { page, pageSize })))
    }
    if (url.pathname === '/api/admin/maintenance-technicians' && options.method === 'POST') {
      return Promise.resolve(provision)
    }
    throw new Error(`Unexpected request: ${options.method || 'GET'} ${url.pathname}`)
  })
}

function directoryCalls() {
  return fetch.mock.calls.filter(([input]) => new URL(input, 'http://localhost').pathname === '/api/admin/users')
}

function provisioningCall() {
  return fetch.mock.calls.find(([input, options = {}]) => (
    new URL(input, 'http://localhost').pathname === '/api/admin/maintenance-technicians'
    && options.method === 'POST'
  ))
}

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
  installApi()
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

describe('Admin Users directory', () => {
  it('labels the Users workspace as User Management in the top bar', () => {
    renderRoute()
    const topbar = document.querySelector('.shared-topbar')
    expect(within(topbar).getByText('User Management', { exact: true })).toBeInTheDocument()
    expect(within(topbar).queryByText('Users', { exact: true })).not.toBeInTheDocument()
    expect(within(screen.getByRole('main')).getByRole('heading', { name: 'Users', level: 1 })).toBeInTheDocument()
    expect(within(screen.getByRole('navigation', { name: 'Primary navigation' })).getByRole('link', { name: 'Users' })).toHaveAttribute('aria-current', 'page')
  })

  it('renders only real API fields and the filtered total without unsupported actions', async () => {
    renderRoute()
    const main = screen.getByRole('main')
    expect(within(main).getByRole('heading', { name: 'Users', level: 1 })).toBeInTheDocument()
    expect(await within(main).findByRole('table')).toBeInTheDocument()
    expect(main).toHaveTextContent('2 users in the current results')
    expect(main).toHaveTextContent('Sam Perera')
    expect(main).toHaveTextContent('sam@example.com')
    expect(main).toHaveTextContent('Admin')
    expect(main).toHaveTextContent('Sep 20, 2026')
    expect(main).toHaveTextContent('Nimali Tenant')
    expect(main).toHaveTextContent('Inactive')
    expect(within(main).queryByText(setupToken)).not.toBeInTheDocument()
    expect(within(main).queryByRole('button', { name: /view|deactivate|edit role|delete/i })).not.toBeInTheDocument()

    const [url, options] = directoryCalls()[0]
    const query = new URL(url, 'http://localhost').searchParams
    expect(query.get('page')).toBe('1')
    expect(query.get('pageSize')).toBe('8')
    expect(options.headers.Authorization).toBe('Bearer admin-token')
  })

  it('sends the backend search and filter names and resets pagination to page one', async () => {
    installApi({ directory: (url) => Promise.resolve(json(directoryPage([], {
      page: Number(url.searchParams.get('page')),
      pageSize: Number(url.searchParams.get('pageSize')),
    }))) })
    renderRoute()
    await screen.findByText('No users match these filters')

    await userEvent.type(screen.getByRole('searchbox', { name: 'Search users by name or email' }), '  sam@example.com  ')
    await userEvent.click(screen.getByRole('button', { name: 'Search' }))
    await waitFor(() => expect(directoryCalls().some(([input]) => new URL(input, 'http://localhost').searchParams.get('search') === 'sam@example.com')).toBe(true))

    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Filter users by role' }), 'MaintenanceTechnician')
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Filter users by active status' }), 'false')
    await waitFor(() => {
      const query = new URL(directoryCalls().at(-1)[0], 'http://localhost').searchParams
      expect(Object.fromEntries(query)).toEqual({
        page: '1', pageSize: '8', search: 'sam@example.com', role: 'MaintenanceTechnician', isActive: 'false',
      })
    })
  })

  it('uses returned pagination metadata for next and previous requests', async () => {
    installApi({ directory: (url) => {
      const page = Number(url.searchParams.get('page'))
      const items = page === 1 ? [adminUser] : [tenantUser]
      return Promise.resolve(json(directoryPage(items, { page, pageSize: 8, totalCount: 9 })))
    } })
    renderRoute()
    expect(await screen.findByText('Sam Perera')).toBeInTheDocument()
    expect(screen.getByText('Page 1 of 2')).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Next' }))
    expect(await screen.findByText('Nimali Tenant')).toBeInTheDocument()
    expect(within(screen.getByRole('table')).queryByText('Sam Perera')).not.toBeInTheDocument()
    expect(new URL(directoryCalls().at(-1)[0], 'http://localhost').searchParams.get('page')).toBe('2')

    await userEvent.click(screen.getByRole('button', { name: 'Previous' }))
    await waitFor(() => expect(within(screen.getByRole('table')).getByText('Sam Perera')).toBeInTheDocument())
    expect(new URL(directoryCalls().at(-1)[0], 'http://localhost').searchParams.get('page')).toBe('1')
  })

  it('shows loading and empty results states', async () => {
    let resolveDirectory
    installApi({ directory: () => new Promise((resolve) => { resolveDirectory = resolve }) })
    renderRoute()
    expect(screen.getByRole('status')).toHaveTextContent('Loading user directory')
    resolveDirectory(json(directoryPage([])))
    expect(await screen.findByText('No users match these filters')).toBeInTheDocument()
  })

  it('clears stale rows on error and retries the authorized request', async () => {
    let calls = 0
    installApi({ directory: () => {
      calls += 1
      return Promise.resolve(calls === 1
        ? json({ detail: 'internal trace' }, 500)
        : json(directoryPage([adminUser])))
    } })
    renderRoute()
    expect(await screen.findByText('User directory unavailable')).toBeInTheDocument()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    expect(screen.getByRole('alert')).not.toHaveTextContent('internal trace')

    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    await waitFor(() => expect(within(screen.getByRole('table')).getByText('Sam Perera')).toBeInTheDocument())
    expect(directoryCalls()).toHaveLength(2)
  })

  it.each([
    [401, 'session is no longer valid'],
    [403, 'no longer authorized'],
  ])('shows a clear non-retryable directory access state for %s', async (status, message) => {
    installApi({ directory: Promise.resolve(json({ detail: 'Denied' }, status)) })
    renderRoute()
    expect(await screen.findByText('Directory access unavailable')).toBeInTheDocument()
    expect(screen.getByRole('alert')).toHaveTextContent(message)
    expect(screen.queryByRole('button', { name: 'Try again' })).not.toBeInTheDocument()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })

  it('prevents an older request from replacing newer filter results', async () => {
    let resolveFirst
    installApi({ directory: (url) => {
      if (!url.searchParams.has('role')) return new Promise((resolve) => { resolveFirst = resolve })
      return Promise.resolve(json(directoryPage([tenantUser])))
    } })
    renderRoute()
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Filter users by role' }), 'Tenant')
    expect(await screen.findByText('Nimali Tenant')).toBeInTheDocument()

    resolveFirst(json(directoryPage([adminUser])))
    await waitFor(() => expect(within(screen.getByRole('table')).queryByText('Sam Perera')).not.toBeInTheDocument())
    expect(within(screen.getByRole('table')).getByText('Nimali Tenant')).toBeInTheDocument()
  })
})

describe('Admin Technician provisioning from Users', () => {
  it('reveals the accessible form and preserves focus and close behavior', async () => {
    renderRoute()
    const addButton = screen.getByRole('button', { name: 'Add Technician' })
    await userEvent.click(addButton)

    expect(addButton).toHaveAttribute('aria-expanded', 'true')
    expect(screen.getByRole('dialog', { name: 'Add Technician' })).toHaveAttribute('aria-modal', 'true')
    expect(screen.getByLabelText('Full name')).toHaveFocus()
    expect(document.body.style.overflow).toBe('hidden')
    expect(screen.getByLabelText('Email')).toHaveAttribute('type', 'email')
    expect(screen.getByLabelText('Phone number')).toHaveAttribute('type', 'tel')

    const submit = screen.getByRole('button', { name: 'Create pending Technician' })
    submit.focus()
    await userEvent.tab()
    expect(screen.getByRole('button', { name: 'Close Add Technician panel' })).toHaveFocus()
    await userEvent.keyboard('{Escape}')
    expect(screen.queryByRole('dialog', { name: 'Add Technician' })).not.toBeInTheDocument()
    expect(addButton).toHaveFocus()
  })

  it('opens from the dashboard action URL and confirms before discarding a draft', async () => {
    renderRoute('Admin', '/modules/users?action=add-technician')
    expect(screen.getByLabelText('Full name')).toHaveFocus()
    await userEvent.type(screen.getByLabelText('Full name'), 'Taylor')

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }))
    const confirmation = screen.getByRole('dialog', { name: 'Discard Technician details?' })
    expect(within(confirmation).getByText(/have not been submitted and will be discarded/)).toBeInTheDocument()
    expect(within(confirmation).getByRole('button', { name: 'Keep panel open' })).toHaveFocus()
    await userEvent.click(within(confirmation).getByRole('button', { name: 'Keep panel open' }))
    expect(screen.getByLabelText('Full name')).toHaveValue('Taylor')
    expect(screen.getByRole('button', { name: 'Cancel' })).toHaveFocus()

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }))
    await userEvent.click(within(screen.getByRole('dialog', { name: 'Discard Technician details?' })).getByRole('button', { name: 'Discard and close' }))
    expect(screen.queryByRole('dialog', { name: 'Add Technician' })).not.toBeInTheDocument()
  })

  it('preserves secure setup-link actions and refreshes the directory after creation', async () => {
    let directoryCount = 0
    installApi({ directory: () => {
      directoryCount += 1
      return Promise.resolve(json(directoryPage(directoryCount === 1 ? [adminUser] : [provisionedUser, adminUser])))
    } })
    renderRoute()
    await screen.findByText('Sam Perera')
    await fillForm()
    await userEvent.click(screen.getByRole('button', { name: 'Create pending Technician' }))

    const successHeading = await screen.findByRole('heading', { name: 'Securely deliver the setup link' })
    expect(successHeading).toHaveFocus()
    const [url, options] = provisioningCall()
    expect(new URL(url, 'http://localhost').pathname).toBe('/api/admin/maintenance-technicians')
    expect(options.headers.Authorization).toBe('Bearer admin-token')
    expect(JSON.parse(options.body)).toEqual({
      fullName: 'Taylor Technician', email: 'tech@example.com', phoneNumber: '+94770000001',
    })
    const setupLink = screen.getByLabelText('One-time password-setup link')
    expect(setupLink.value).toContain(`/setup-password#token=${setupToken}`)
    expect(JSON.stringify({ ...sessionStorage, ...localStorage })).not.toContain(setupToken)

    await waitFor(() => expect(directoryCalls()).toHaveLength(2))
    const table = screen.getByRole('table')
    expect(within(table).getByText('Taylor Technician')).toBeInTheDocument()
    expect(within(table).queryByText(setupToken)).not.toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: 'Copy link' }))
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(setupLink.value)
    expect(await screen.findByText(/Setup link copied/)).toHaveAttribute('role', 'status')

    await userEvent.click(screen.getByRole('button', { name: 'Close Add Technician panel' }))
    const confirmation = screen.getByRole('dialog', { name: 'Clear the setup link?' })
    expect(within(confirmation).getByText(/permanently clears the one-time setup link/)).toBeInTheDocument()
    expect(within(confirmation).getByRole('button', { name: 'Keep panel open' })).toHaveFocus()
    await userEvent.click(within(confirmation).getByRole('button', { name: 'Keep panel open' }))
    expect(setupLink).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Clear setup link' }))
    expect(screen.queryByLabelText('One-time password-setup link')).not.toBeInTheDocument()
    expect(screen.getByLabelText('Full name')).toHaveFocus()
  })

  it('preserves client validation, duplicate-email handling, and submission state', async () => {
    renderRoute()
    await openForm()
    await userEvent.click(screen.getByRole('button', { name: 'Create pending Technician' }))
    expect(screen.getByRole('alert')).toHaveTextContent('full name')
    expect(provisioningCall()).toBeUndefined()

    await fillForm()
    installApi({ provision: json({ detail: 'An account with this email already exists.' }, 409) })
    await userEvent.click(screen.getByRole('button', { name: 'Create pending Technician' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('An account with this email already exists.')
  })

  it('disables form controls while account creation is pending', async () => {
    let resolveProvision
    installApi({ provision: new Promise((resolve) => { resolveProvision = resolve }) })
    renderRoute()
    await fillForm()
    await userEvent.click(screen.getByRole('button', { name: 'Create pending Technician' }))
    expect(screen.getByRole('button', { name: 'Creating pending account...' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Cancel' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Close Add Technician panel' })).toBeDisabled()
    resolveProvision(json(provisionResponse, 201))
    expect(await screen.findByRole('heading', { name: 'Securely deliver the setup link' })).toBeInTheDocument()
  })
})

describe('Admin Users access and shell', () => {
  it('keeps Users active and preserves shared navigation and account actions', () => {
    renderRoute()
    const nav = screen.getByRole('navigation', { name: 'Primary navigation' })
    const usersLink = within(nav).getByRole('link', { name: 'Users' })
    expect(usersLink).toHaveAttribute('href', '/modules/users')
    expect(usersLink).toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('link', { name: 'Notifications' })).toHaveAttribute('href', '/notifications')
    expect(within(nav).queryByRole('link', { name: 'Profile' })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Profile for Sam Perera' })).toBeInTheDocument()
    expect(within(nav).getByRole('button', { name: 'Logout' })).toBeInTheDocument()
  })

  it.each(['Tenant', 'Landlord', 'MaintenanceTechnician'])('blocks %s from the Admin Users route', (role) => {
    renderRoute(role)
    expect(screen.getByRole('heading', { name: 'Not accessible' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Add Technician' })).not.toBeInTheDocument()
    expect(fetch).not.toHaveBeenCalled()
  })
})
